import XCTest
@testable import UI
import GameWorld
import GameEngine
import Audio

/// Drives a real multi-hand session and checks the reworked audio layer end to
/// end (D-029): the director never voices the croupier, the croupier voices are
/// all institutional and at most once per hand, and bot voicelines are
/// deterministic. Also prints a sound log for one hand (the FASE 2 verification).
@MainActor
final class AudioIntegrationTests: XCTestCase {

    private func bot(_ p: Personality, _ s: UInt64) -> BotActionProvider {
        BotActionProvider(HeuristicBot(personality: p, seed: s, equitySamples: 30))
    }

    private func runSession() async throws -> [EventPayload] {
        let driver = SessionDriver(capacity: 3, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 300, provider: bot(.eagerNovice, 1)),
            SeatAssignment(position: 1, playerID: 1, chips: 300, provider: bot(.conservativeRock, 2)),
            SeatAssignment(position: 2, playerID: 2, chips: 300, provider: bot(.hotAggressor, 3)),
        ], buttonPosition: 0, smallBlind: 10, bigBlind: 20, seed: 42)
        let stream = await driver.events(as: .spectator)
        _ = try await driver.run(maxHands: 6)
        await driver.endSession()
        var events: [EventPayload] = []
        for await e in stream { events.append(e.payload) }
        return events
    }

    private func directorRecorder(_ events: [EventPayload], seed: UInt64 = 7) -> RecordingAudioService {
        let audio = RecordingAudioService()
        let director = AudioDirector(audio: audio, heroSeatID: 0,
                                     characters: [1: .rock, 2: .aggressor], seed: seed, fastMode: true)
        for e in events { director.handle(e) }
        return audio
    }

    func testDirectorNeverPlaysCroupierAndDoesPlayTableSounds() async throws {
        let events = try await runSession()
        let audio = directorRecorder(events)
        XCTAssertTrue(audio.croupierPlays.isEmpty, "the director must not play any croupier voice (D-029)")
        XCTAssertTrue(audio.played.contains { $0.category == .table }, "physical table sounds should play")
    }

    func testBotVoicelinesAreDeterministicGivenSeed() async throws {
        let events = try await runSession()
        XCTAssertEqual(directorRecorder(events, seed: 5).botVoicePlays,
                       directorRecorder(events, seed: 5).botVoicePlays)
    }

    func testCroupierVoicesAreAllInstitutionalAndPotIsOncePerHand() async throws {
        let events = try await runSession()
        let audio = RecordingAudioService()
        let conductor = SpeechConductor(audio: audio, announcer: Announcer())
        for e in events {
            if case .handBegan = e { conductor.handBegan() }
            let plan = SpeechMap.plan(for: e, heroSeatID: 0, names: [:])
            conductor.say(croupier: plan.croupier, synthesis: nil)
        }
        try? await Task.sleep(nanoseconds: 400_000_000)

        let institutional = Set([
            SoundCatalog.voHandStart, SoundCatalog.voBlindSmall, SoundCatalog.voBlindBig,
            SoundCatalog.voFlop, SoundCatalog.voTurn, SoundCatalog.voRiver, SoundCatalog.voShowdown,
            SoundCatalog.voActionAllIn, SoundCatalog.voPotAwarded, SoundCatalog.voSplitPot,
        ].map(\.rawValue))
        for id in audio.croupierPlays {
            XCTAssertTrue(institutional.contains(id.rawValue), "\(id.rawValue) is not an institutional croupier voice")
        }
        let hands = events.filter { if case .handBegan = $0 { return true }; return false }.count
        let potVoices = audio.croupierPlays.filter { $0 == SoundCatalog.voPotAwarded || $0 == SoundCatalog.voSplitPot }.count
        XCTAssertLessThanOrEqual(potVoices, hands, "pot voice must play at most once per hand")
        XCTAssertGreaterThan(hands, 0)
    }

    /// Prints the ordered sound sources for the first hand, per the FASE 2 check.
    func testPrintSoundLogForFirstHand() async throws {
        let events = try await runSession()
        guard let start = events.firstIndex(where: { if case .handBegan = $0 { return true }; return false }) else {
            return XCTFail("no hand in the session")
        }
        var log = "\n=== SOUND LOG — first hand (D-029 mapping) ===\n"
        for e in events[start...] {
            if case .handBegan = e, e != events[start] { break } // stop at the next hand
            let physical = AudioScore.cues(for: e, heroSeatID: 0).compactMap { cue -> String? in
                if case let .play(id, cat) = cue { return "\(cat) \(id.rawValue)" }; return nil
            }
            let plan = SpeechMap.plan(for: e, heroSeatID: 0, names: [1: "Novice", 2: "Rock"])
            var sources: [String] = physical
            if let c = plan.croupier { sources.append("croupier \(c.rawValue)") }
            if let s = plan.synthesis { sources.append("synth \(SpeechMap.text(for: s))") }
            log += "• \(label(e)) → \(sources.isEmpty ? "—" : sources.joined(separator: ", "))\n"
        }
        print(log)
        XCTAssertTrue(log.contains("croupier vo_it_hand_start"))
    }

    private func label(_ e: EventPayload) -> String {
        switch e {
        case .handBegan: return "handBegan"
        case .blindPosted: return "blindPosted"
        case .holeCardsDealt: return "holeCardsDealt"
        case .privateHoleCards: return "privateHoleCards"
        case .playerActed: return "playerActed"
        case .streetOpened: return "streetOpened"
        case .handShown: return "handShown"
        case .potAwarded: return "potAwarded"
        case .handEnded: return "handEnded"
        case .playerBusted: return "playerBusted"
        default: return "other"
        }
    }
}
