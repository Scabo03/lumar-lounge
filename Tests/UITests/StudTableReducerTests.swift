import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine

/// The pure Stud table reducer (D-077): folding events into presentation state, with the
/// per-seat UP cards that power the accessibility interrogation, and the house-prize banner.
final class StudTableReducerTests: XCTestCase {

    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    private func started() -> StudTableState {
        var s = StudTableState(seats: [0, 1, 2].map { StudSeatPresentation(id: $0, position: $0, chips: 3000) },
                               heroSeatID: 0)
        s = StudTableReducer.reduce(s, .handBegan(handNumber: 0, ante: 25, bringIn: 25, bet: 50,
            seats: [0, 1, 2].map { StudSeatSnapshot(seatID: $0, position: $0, chips: 3000) }))
        return s
    }

    func testAnteAndBringInDeductAndBuildThePot() {
        var s = started()
        s = StudTableReducer.reduce(s, .antePosted(seatID: 0, amount: 25, isAllIn: false))
        s = StudTableReducer.reduce(s, .antePosted(seatID: 1, amount: 25, isAllIn: false))
        s = StudTableReducer.reduce(s, .bringInPosted(seatID: 1, amount: 25, isAllIn: false))
        XCTAssertEqual(s.pot, 75)
        XCTAssertEqual(s.seat(0)?.chips, 2975)
        XCTAssertEqual(s.seat(1)?.chips, 2950)
        XCTAssertTrue(s.seat(1)?.isBringIn ?? false)
    }

    func testUpCardsArePublicPerSeatAndAccumulate() {
        var s = started()
        s = StudTableReducer.reduce(s, .upCardDealt(seatID: 1, card: c(.king, .hearts), street: .third))
        s = StudTableReducer.reduce(s, .upCardDealt(seatID: 1, card: c(.ten, .hearts), street: .fourth))
        XCTAssertEqual(s.seat(1)?.upCards, [c(.king, .hearts), c(.ten, .hearts)],
                       "an opponent's up cards accumulate (the interrogation reads them all)")
    }

    func testHeroDownCardsAreCollectedForTheHeroOnly() {
        var s = started()
        s = StudTableReducer.reduce(s, .privateDownCards(seatID: 0, cards: [c(.ace, .spades), c(.king, .spades)]))
        s = StudTableReducer.reduce(s, .privateDownCards(seatID: 0, cards: [c(.two, .clubs)]))   // seventh
        XCTAssertEqual(s.heroDown, [c(.ace, .spades), c(.king, .spades), c(.two, .clubs)])
        // A non-hero private event never touches heroDown.
        s = StudTableReducer.reduce(s, .privateDownCards(seatID: 1, cards: [c(.queen, .diamonds)]))
        XCTAssertEqual(s.heroDown?.count, 3)
    }

    func testFoldClearsTheSeatBoard() {
        var s = started()
        s = StudTableReducer.reduce(s, .upCardDealt(seatID: 1, card: c(.king, .hearts), street: .third))
        s = StudTableReducer.reduce(s, .playerActed(seatID: 1, action: .folded))
        XCTAssertTrue(s.seat(1)?.isFolded ?? false)
        XCTAssertTrue(s.seat(1)?.upCards.isEmpty ?? false, "a folded seat mucks — no board to read")
    }

    func testHousePrizeSetsTheBanner() {
        var s = started()
        s = StudTableReducer.reduce(s, .housePrizeAwarded(playerID: 0, amount: 200))
        XCTAssertEqual(s.housePrizeAwarded, 200)
        // handBegan clears it for the next hand.
        s = StudTableReducer.reduce(s, .handBegan(handNumber: 1, ante: 25, bringIn: 25, bet: 50,
            seats: [0, 1, 2].map { StudSeatSnapshot(seatID: $0, position: $0, chips: 3000) }))
        XCTAssertEqual(s.housePrizeAwarded, 0)
    }

    func testHandShownRevealsSevenCardsAndHandEndedSetsChips() {
        var s = started()
        let seven = [c(.ace, .spades), c(.ace, .hearts), c(.king, .spades), c(.king, .hearts),
                     c(.queen, .clubs), c(.two, .diamonds), c(.five, .spades)]
        s = StudTableReducer.reduce(s, .handShown(seatID: 0, cards: seven, category: .twoPair, bestFive: Array(seven.prefix(5))))
        XCTAssertEqual(s.seat(0)?.revealed?.count, 7)
        s = StudTableReducer.reduce(s, .handEnded(handNumber: 0, wentToShowdown: true, payouts: [0: 300], chips: [0: 3200, 1: 2900, 2: 2900]))
        XCTAssertEqual(s.seat(0)?.chips, 3200)
    }

    func testHeroCardsCombinesDownAndUp() {
        var s = started()
        s = StudTableReducer.reduce(s, .privateDownCards(seatID: 0, cards: [c(.ace, .spades), c(.king, .spades)]))
        s = StudTableReducer.reduce(s, .upCardDealt(seatID: 0, card: c(.queen, .spades), street: .third))
        XCTAssertEqual(s.heroCards, [c(.ace, .spades), c(.king, .spades), c(.queen, .spades)],
                       "the hero's cards are their down cards followed by their up cards")
    }
}
