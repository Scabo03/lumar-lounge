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

    private func handBegan() -> EventPayload {
        .handBegan(handNumber: 0, buttonPosition: 0, buttonSeatID: 0, smallBlindSeatID: 1, bigBlindSeatID: 2,
                   smallBlind: 10, bigBlind: 20, seats: [])
    }

    // MARK: - Pure mapping per event type

    func testSessionBeganStartsAmbient() {
        XCTAssertEqual(cues(.sessionBegan(seats: [], smallBlind: 10, bigBlind: 20)),
                       [.startAmbient(SoundCatalog.ambLoungeCalm1)])
    }

    func testHandBeganShufflesAndAnnounces() {
        XCTAssertEqual(cues(handBegan()),
                       [.play(SoundCatalog.tblShuffle, .table), .play(SoundCatalog.voHandStart, .croupier)])
    }

    func testBlindsPlayChipsAndCroupier() {
        XCTAssertEqual(cues(.blindPosted(seatID: 1, blind: .small, amount: 10, isAllIn: false)),
                       [.play(SoundCatalog.tblChipsSingle, .table), .play(SoundCatalog.voBlindSmall, .croupier)])
        XCTAssertEqual(cues(.blindPosted(seatID: 2, blind: .big, amount: 20, isAllIn: false)),
                       [.play(SoundCatalog.tblChipsSingle, .table), .play(SoundCatalog.voBlindBig, .croupier)])
    }

    func testHoleCardsDealt() {
        XCTAssertEqual(cues(.holeCardsDealt(seatID: 1)), [.play(SoundCatalog.tblCardDealSingle, .table)])
    }

    func testStreets() {
        XCTAssertEqual(cues(.streetOpened(street: .flop, communityCards: [])),
                       [.play(SoundCatalog.tblCardsDealFlop, .table), .play(SoundCatalog.voFlop, .croupier)])
        XCTAssertEqual(cues(.streetOpened(street: .turn, communityCards: [])),
                       [.play(SoundCatalog.tblCardFlipSingle, .table), .play(SoundCatalog.voTurn, .croupier)])
        XCTAssertEqual(cues(.streetOpened(street: .river, communityCards: [])),
                       [.play(SoundCatalog.tblCardFlipSingle, .table), .play(SoundCatalog.voRiver, .croupier)])
    }

    func testActionsAnnouncedByCroupier() {
        XCTAssertEqual(cues(.playerActed(seatID: 1, action: .folded)),
                       [.play(SoundCatalog.tblMuck, .table), .play(SoundCatalog.voActionFold, .croupier)])
        XCTAssertEqual(cues(.playerActed(seatID: 1, action: .checked)),
                       [.play(SoundCatalog.voActionCheck, .croupier)])
        XCTAssertEqual(cues(.playerActed(seatID: 1, action: .called(amount: 20, isAllIn: false))),
                       [.play(SoundCatalog.tblChipsStack, .table), .play(SoundCatalog.voActionCall, .croupier)])
    }

    func testAllInPlaysBigChipsCroupierAndDramaticEffect() {
        let result = cues(.playerActed(seatID: 1, action: .raised(to: 200, amount: 200, isAllIn: true)))
        XCTAssertTrue(result.contains(.play(SoundCatalog.tblChipsBetLarge, .table)))
        XCTAssertTrue(result.contains(.play(SoundCatalog.voActionAllIn, .croupier)))
        XCTAssertTrue(result.contains(.play(SoundCatalog.fxAllInDramatic, .effect)))
    }

    func testPotAwardedAndSplit() {
        XCTAssertEqual(cues(.potAwarded(potIndex: 0, amount: 100, winnerSeatIDs: [1])),
                       [.play(SoundCatalog.tblChipsPotCollect, .table), .play(SoundCatalog.voPotAwarded, .croupier)])
        XCTAssertEqual(cues(.potAwarded(potIndex: 0, amount: 100, winnerSeatIDs: [1, 2])),
                       [.play(SoundCatalog.tblChipsPotCollect, .table), .play(SoundCatalog.voSplitPot, .croupier)])
    }

    func testBustSounds() {
        XCTAssertEqual(cues(.playerBusted(playerID: 0)), [.play(SoundCatalog.fxBustHero, .effect)])
        XCTAssertEqual(cues(.playerBusted(playerID: 1)), [.play(SoundCatalog.fxBustPlayer, .effect)])
    }

    func testHandEndedAndSessionEndedAreSilentInTheMapping() {
        XCTAssertEqual(cues(.handEnded(handNumber: 0, wentToShowdown: true, board: [], payouts: [:], chips: [:])), [])
        XCTAssertEqual(cues(.sessionEnded(reason: .stopped)), [])
    }

    // MARK: - Determinism

    func testProbabilisticCuesAreDeterministic() {
        let voices = [1: BotVoiceProfile(assertive: SoundCatalog.vobNoviceExcited, letdown: SoundCatalog.vobNoviceDisappointed)]
        let event = EventPayload.playerActed(seatID: 1, action: .raised(to: 60, amount: 60, isAllIn: false))
        XCTAssertEqual(cues(event, voices: voices, seed: 99), cues(event, voices: voices, seed: 99))
    }

    // MARK: - Integration: the audio consumer reacts to the whole flow

    @MainActor
    func testAudioDirectorReactsToWholeSession() async throws {
        let recorder = RecordingAudioService()
        let voices = [
            0: BotVoiceProfile(assertive: SoundCatalog.vobNoviceExcited, letdown: SoundCatalog.vobNoviceDisappointed),
            1: BotVoiceProfile(assertive: SoundCatalog.vobRockGrunt, letdown: SoundCatalog.vobRockGrunt),
            2: BotVoiceProfile(assertive: SoundCatalog.vobAggressorConfident, letdown: SoundCatalog.vobAggressorBluffGiveaway),
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

        XCTAssertGreaterThan(handled, 0)
        XCTAssertEqual(recorder.ambient, [SoundCatalog.ambLoungeCalm1])
        XCTAssertTrue(recorder.played.contains { $0.category == .table })
        XCTAssertTrue(recorder.played.contains { $0.category == .croupier })
        XCTAssertGreaterThan(recorder.stoppedAll, 0)
    }
}
