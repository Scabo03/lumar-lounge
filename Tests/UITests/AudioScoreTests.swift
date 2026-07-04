import XCTest
@testable import UI
import GameWorld
import GameEngine
import Audio

/// Records what the audio layer was asked to do, for the integration test.
private final class RecordingAudioService: AudioServicing {
    var ambient: [SoundID] = []
    var played: [(id: SoundID, category: SoundCategory)] = []
    var stoppedAll = 0
    func startAmbient(_ id: SoundID) { ambient.append(id) }
    func play(_ id: SoundID, category: SoundCategory) { played.append((id, category)) }
    func stopAll() { stoppedAll += 1 }
    func setMasterVolume(_ volume: Float) {}
    func setMuted(_ muted: Bool) {}
}

final class AudioScoreTests: XCTestCase {

    private func cues(_ payload: EventPayload, voices: [Int: BotVoiceProfile] = [:], seed: UInt64 = 1) -> [SoundCue] {
        var rng = SeededGenerator(seed: seed)
        return AudioScore.cues(for: payload, heroSeatID: 0, voices: voices, rng: &rng)
    }

    // MARK: - Pure mapping per event type

    func testSessionBeganStartsAmbient() {
        XCTAssertEqual(cues(.sessionBegan(seats: [], smallBlind: 10, bigBlind: 20)),
                       [.startAmbient(SoundCatalog.ambientLounge)])
    }

    func testHoleCardsAndBlindsAreTableSounds() {
        XCTAssertEqual(cues(.holeCardsDealt(seatID: 1)), [.play(SoundCatalog.cardDeal, .table)])
        XCTAssertEqual(cues(.blindPosted(seatID: 1, blind: .small, amount: 10, isAllIn: false)),
                       [.play(SoundCatalog.chipsBet, .table)])
    }

    func testStreetsPlayFlipAndCroupierVoice() {
        XCTAssertEqual(cues(.streetOpened(street: .flop, communityCards: [])),
                       [.play(SoundCatalog.cardFlip, .table), .play(SoundCatalog.voFlop, .croupier)])
        XCTAssertEqual(cues(.streetOpened(street: .turn, communityCards: [])),
                       [.play(SoundCatalog.cardFlip, .table), .play(SoundCatalog.voTurn, .croupier)])
        XCTAssertEqual(cues(.streetOpened(street: .river, communityCards: [])),
                       [.play(SoundCatalog.cardFlip, .table), .play(SoundCatalog.voRiver, .croupier)])
    }

    func testFoldMucksAndCheckIsSilent() {
        XCTAssertEqual(cues(.playerActed(seatID: 1, action: .folded)), [.play(SoundCatalog.cardMuck, .table)])
        XCTAssertEqual(cues(.playerActed(seatID: 1, action: .checked)), [])
    }

    func testAllInAddsCroupierAndDramaticEffect() {
        let result = cues(.playerActed(seatID: 1, action: .raised(to: 200, amount: 200, isAllIn: true)))
        XCTAssertTrue(result.contains(.play(SoundCatalog.chipsBet, .table)))
        XCTAssertTrue(result.contains(.play(SoundCatalog.voAllIn, .croupier)))
        XCTAssertTrue(result.contains(.play(SoundCatalog.fxAllInDramatic, .effect)))
    }

    func testHeroWinningPotPlaysWinFx() {
        XCTAssertEqual(cues(.potAwarded(potIndex: 0, amount: 100, winnerSeatIDs: [0])),
                       [.play(SoundCatalog.fxWinHand, .effect)])
    }

    func testEventsWithoutSoundReturnNothing() {
        XCTAssertEqual(cues(.handShown(seatID: 1, holeCards: [], category: .pair, bestFive: [])), [])
        XCTAssertEqual(cues(.handEnded(handNumber: 0, wentToShowdown: true, board: [], payouts: [:], chips: [:])), [])
    }

    // MARK: - Determinism

    func testProbabilisticCuesAreDeterministicForAGivenSeed() {
        let voices = [1: BotVoiceProfile(confident: SoundCatalog.vobNoviceHappy,
                                         disappointed: SoundCatalog.vobNoviceDisappointed)]
        let event = EventPayload.playerActed(seatID: 1, action: .raised(to: 60, amount: 60, isAllIn: false))
        XCTAssertEqual(cues(event, voices: voices, seed: 99), cues(event, voices: voices, seed: 99))
    }

    // MARK: - Integration: the audio consumer reacts to the whole flow

    @MainActor
    func testAudioDirectorReactsToWholeSession() async throws {
        let recorder = RecordingAudioService()
        let voices = [
            0: BotVoiceProfile(confident: SoundCatalog.vobNoviceHappy, disappointed: SoundCatalog.vobNoviceDisappointed),
            1: BotVoiceProfile(confident: SoundCatalog.vobRockConfident, disappointed: SoundCatalog.vobRockDisappointed),
            2: BotVoiceProfile(confident: SoundCatalog.vobAggressorConfident, disappointed: SoundCatalog.vobAggressorDisappointed),
        ]
        let director = AudioDirector(audio: recorder, heroSeatID: 0, voices: voices, seed: 7, fastMode: true)

        func bot(_ p: Personality, _ s: UInt64) -> BotActionProvider {
            BotActionProvider(HeuristicBot(personality: p, seed: s, equitySamples: 30))
        }
        let driver = SessionDriver(capacity: 3, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 300, provider: bot(.eagerNovice, 1)),
            SeatAssignment(position: 1, playerID: 1, chips: 300, provider: bot(.conservativeRock, 2)),
            SeatAssignment(position: 2, playerID: 2, chips: 300, provider: bot(.hotAggressor, 3)),
        ], buttonPosition: 0, smallBlind: 10, bigBlind: 20, seed: 42)

        let stream = await driver.events(as: .spectator)
        _ = try await driver.run(maxHands: 6)
        await driver.endSession()

        var handled = 0
        for await event in stream { director.handle(event.payload); handled += 1 }

        XCTAssertGreaterThan(handled, 0, "no events received")
        XCTAssertEqual(recorder.ambient, [SoundCatalog.ambientLounge], "ambient should start exactly once")
        XCTAssertTrue(recorder.played.contains { $0.category == .table }, "table sounds should have played")
        XCTAssertGreaterThan(recorder.stoppedAll, 0, "stopAll should fire on session end")
    }
}
