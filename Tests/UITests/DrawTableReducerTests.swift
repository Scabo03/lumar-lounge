import XCTest
@testable import UI
import GameWorld
import GameEngine

/// Tests for the pure Five-Card Draw presentation reducer (D-044): events fold
/// into `DrawTableState` deterministically, with no SwiftUI or game logic.
final class DrawTableReducerTests: XCTestCase {

    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    private func seatedState() -> DrawTableState {
        var s = DrawTableState(seats: (0..<4).map { DrawSeatPresentation(id: $0, position: $0, chips: 2000) },
                               heroSeatID: 0)
        s = DrawTableReducer.reduce(s, .handBegan(handNumber: 0, buttonPosition: 0, buttonSeatID: 0,
                                                  ante: 10, smallBet: 20, bigBet: 40, carriedPot: 0,
                                                  seats: (0..<4).map { DrawSeatSnapshot(seatID: $0, position: $0, chips: 2000) }))
        return s
    }

    func testHandBeganSetsPhaseButtonAndCarriedPot() {
        var s = DrawTableState(seats: (0..<4).map { DrawSeatPresentation(id: $0, position: $0, chips: 2000) }, heroSeatID: 0)
        s = DrawTableReducer.reduce(s, .handBegan(handNumber: 3, buttonPosition: 1, buttonSeatID: 1,
                                                  ante: 10, smallBet: 20, bigBet: 40, carriedPot: 80,
                                                  seats: (0..<4).map { DrawSeatSnapshot(seatID: $0, position: $0, chips: 2000) }))
        XCTAssertEqual(s.phase, .firstBet)
        XCTAssertEqual(s.buttonSeatID, 1)
        XCTAssertEqual(s.pot, 80)          // starts at the carried pot
        XCTAssertEqual(s.carriedPot, 80)
        XCTAssertTrue(s.seat(1)!.isButton)
    }

    func testAntePostedSubtractsAndAddsToPot() {
        var s = seatedState()
        s = DrawTableReducer.reduce(s, .antePosted(seatID: 0, amount: 10, isAllIn: false))
        XCTAssertEqual(s.seat(0)!.chips, 1990)
        XCTAssertEqual(s.pot, 10)
    }

    func testPrivateCardsSetHeroHandOnly() {
        var s = seatedState()
        let mine = [c(.ace, .spades), c(.king, .spades), c(.two, .hearts), c(.seven, .clubs), c(.nine, .diamonds)]
        s = DrawTableReducer.reduce(s, .privateCards(seatID: 0, cards: mine))
        XCTAssertEqual(s.heroCards, mine)
        // A private-cards event for another seat is ignored on the hero display.
        s = DrawTableReducer.reduce(s, .privateCards(seatID: 1, cards: mine))
        XCTAssertEqual(s.heroCards, mine)
    }

    func testPotOpenedMarksOpener() {
        var s = seatedState()
        s = DrawTableReducer.reduce(s, .potOpened(seatID: 2, hasOpeners: true))
        XCTAssertTrue(s.seat(2)!.isOpener)
    }

    func testFoldMucksHeroCards() {
        var s = seatedState()
        s = DrawTableReducer.reduce(s, .privateCards(seatID: 0, cards: Array(repeating: c(.ace, .spades), count: 5)))
        s = DrawTableReducer.reduce(s, .playerActed(seatID: 0, action: .folded, round: .first))
        XCTAssertTrue(s.seat(0)!.isFolded)
        XCTAssertNil(s.heroCards)
    }

    func testDrawPhaseAndDiscardCount() {
        var s = seatedState()
        s = DrawTableReducer.reduce(s, .drawPhaseBegan)
        XCTAssertEqual(s.phase, .draw)
        s = DrawTableReducer.reduce(s, .playerDrew(seatID: 1, discardCount: 3))
        XCTAssertEqual(s.seat(1)!.discardCount, 3)
        s = DrawTableReducer.reduce(s, .secondBetBegan)
        XCTAssertEqual(s.phase, .secondBet)
    }

    func testPassedInSetsBannerAndCarriedPot() {
        var s = seatedState()
        s = DrawTableReducer.reduce(s, .passedIn(carriedPot: 40, consecutivePassed: 1))
        XCTAssertTrue(s.passedIn)
        XCTAssertEqual(s.carriedPot, 40)
        XCTAssertEqual(s.consecutivePassed, 1)
    }

    func testOpenersDisqualifiedFlagsSeat() {
        var s = seatedState()
        s = DrawTableReducer.reduce(s, .openersDisqualified(seatID: 3))
        XCTAssertTrue(s.seat(3)!.isDisqualified)
    }

    func testHandEndedUpdatesChips() {
        var s = seatedState()
        s = DrawTableReducer.reduce(s, .handEnded(handNumber: 0, outcome: .showdown,
                                                  chips: [0: 2100, 1: 1900, 2: 2000, 3: 2000]))
        XCTAssertEqual(s.seat(0)!.chips, 2100)
        XCTAssertEqual(s.seat(1)!.chips, 1900)
    }
}
