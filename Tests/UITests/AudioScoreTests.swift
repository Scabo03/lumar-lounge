import XCTest
@testable import UI
import GameWorld
import GameEngine
import Audio

/// The pure NON-spoken layer (D-029): physical table sounds and effects only —
/// never a croupier voice (that is the conductor's job).
final class AudioScoreTests: XCTestCase {

    private func cues(_ payload: EventPayload) -> [SoundCue] {
        AudioScore.cues(for: payload, heroSeatID: 0)
    }

    private func handBegan() -> EventPayload {
        .handBegan(handNumber: 0, buttonPosition: 0, buttonSeatID: 0, smallBlindSeatID: 1, bigBlindSeatID: 2,
                   smallBlind: 10, bigBlind: 20, seats: [])
    }

    private func hasCroupier(_ cues: [SoundCue]) -> Bool {
        cues.contains { if case .play(_, .croupier) = $0 { return true }; return false }
    }

    func testHandBeganShuffles() {
        XCTAssertEqual(cues(handBegan()), [.play(SoundCatalog.tblShuffle, .table)])
    }

    func testBlindsAndHoleCardsArePhysicalOnly() {
        XCTAssertEqual(cues(.blindPosted(seatID: 1, blind: .small, amount: 10, isAllIn: false)),
                       [.play(SoundCatalog.tblChipsSingle, .table)])
        XCTAssertEqual(cues(.holeCardsDealt(seatID: 1)), [.play(SoundCatalog.tblCardDealSingle, .table)])
    }

    func testStreetsArePhysicalOnly() {
        XCTAssertEqual(cues(.streetOpened(street: .flop, communityCards: [])), [.play(SoundCatalog.tblCardsDealFlop, .table)])
        XCTAssertEqual(cues(.streetOpened(street: .turn, communityCards: [])), [.play(SoundCatalog.tblCardFlipSingle, .table)])
        XCTAssertEqual(cues(.streetOpened(street: .river, communityCards: [])), [.play(SoundCatalog.tblCardFlipSingle, .table)])
    }

    func testActionsArePhysicalOnly() {
        XCTAssertEqual(cues(.playerActed(seatID: 1, action: .folded)), [.play(SoundCatalog.tblMuck, .table)])
        XCTAssertEqual(cues(.playerActed(seatID: 1, action: .checked)), [])
        XCTAssertEqual(cues(.playerActed(seatID: 1, action: .called(amount: 20, isAllIn: false))),
                       [.play(SoundCatalog.tblChipsStack, .table)])
    }

    func testAllInPlaysBigChipsAndDramaticEffectWithoutCroupier() {
        let result = cues(.playerActed(seatID: 1, action: .raised(to: 200, amount: 200, isAllIn: true)))
        XCTAssertTrue(result.contains(.play(SoundCatalog.tblChipsBetLarge, .table)))
        XCTAssertTrue(result.contains(.play(SoundCatalog.fxAllInDramatic, .effect)))
        XCTAssertFalse(hasCroupier(result))
    }

    func testShowdownAndPotArePhysicalOnly() {
        XCTAssertEqual(cues(.handShown(seatID: 1, holeCards: [], category: .pair, bestFive: [])),
                       [.play(SoundCatalog.tblCardFlipSingle, .table)])
        XCTAssertEqual(cues(.potAwarded(potIndex: 0, amount: 100, winnerSeatIDs: [1])),
                       [.play(SoundCatalog.tblChipsPotCollect, .table)])
    }

    func testBustSounds() {
        XCTAssertEqual(cues(.playerBusted(playerID: 0)), [.play(SoundCatalog.fxBustHero, .effect)])
        XCTAssertEqual(cues(.playerBusted(playerID: 1)), [.play(SoundCatalog.fxBustPlayer, .effect)])
    }

    func testNoCroupierVoiceInThePhysicalLayerEver() {
        let events: [EventPayload] = [
            handBegan(),
            .blindPosted(seatID: 1, blind: .small, amount: 10, isAllIn: false),
            .streetOpened(street: .flop, communityCards: []),
            .handShown(seatID: 1, holeCards: [], category: .pair, bestFive: []),
            .potAwarded(potIndex: 0, amount: 100, winnerSeatIDs: [1]),
            .playerActed(seatID: 1, action: .raised(to: 60, amount: 60, isAllIn: false)),
            .playerActed(seatID: 1, action: .raised(to: 300, amount: 300, isAllIn: true)),
        ]
        for e in events { XCTAssertFalse(hasCroupier(cues(e)), "\(e) must not emit a croupier voice") }
    }
}
