import XCTest
@testable import UI
import GameWorld
import GameEngine

/// The pure Omaha table reducer (D-066): folds `OmahaEventPayload`s into the
/// presentation state — four hole cards, the board, the pot, chips, the button.
final class OmahaTableReducerTests: XCTestCase {

    private func snap(_ id: Int, _ chips: Int) -> OmahaSeatSnapshot {
        OmahaSeatSnapshot(seatID: id, position: id, chips: chips)
    }
    private let c = { (r: Rank, s: Suit) in Card(r, s) }

    private func reduce(_ payloads: [OmahaEventPayload], from start: OmahaTableState) -> OmahaTableState {
        payloads.reduce(start) { OmahaTableReducer.reduce($0, $1) }
    }

    func testHandFlowUpdatesBoardPotHeroCardsAndButton() {
        var state = OmahaTableState(heroSeatID: 0)
        let hero = [c(.ace, .spades), c(.king, .spades), c(.ten, .hearts), c(.five, .clubs)]
        let flop = [c(.two, .diamonds), c(.seven, .clubs), c(.queen, .hearts)]

        state = reduce([
            .sessionBegan(seats: [snap(0, 1000), snap(1, 1000), snap(2, 1000)], smallBlind: 25, bigBlind: 50),
            .handBegan(handNumber: 0, buttonPosition: 0, buttonSeatID: 0, smallBlindSeatID: 1, bigBlindSeatID: 2,
                       smallBlind: 25, bigBlind: 50,
                       seats: [snap(0, 1000), snap(1, 1000), snap(2, 1000)]),
            .blindPosted(seatID: 1, blind: .small, amount: 25, isAllIn: false),
            .blindPosted(seatID: 2, blind: .big, amount: 50, isAllIn: false),
            .holeCardsDealt(seatID: 0),
            .privateHoleCards(seatID: 0, cards: hero),
            .playerActed(seatID: 0, action: .called(amount: 50, isAllIn: false)),
            .streetOpened(street: .flop, communityCards: flop),
        ], from: state)

        XCTAssertEqual(state.heroCards, hero)                 // four hole cards
        XCTAssertEqual(state.board, flop)                    // three community cards
        XCTAssertEqual(state.pot, 25 + 50 + 50)              // both blinds + hero's call
        XCTAssertEqual(state.buttonSeatID, 0)
        XCTAssertTrue(state.seat(0)?.isButton ?? false)
        XCTAssertEqual(state.seat(0)?.chips, 1000 - 50)      // hero called 50
        XCTAssertEqual(state.smallBlind, 25)
        XCTAssertEqual(state.bigBlind, 50)
    }

    func testFoldClearsHeroCardsAndMarksFolded() {
        var state = OmahaTableState(seats: [OmahaSeatPresentation(id: 0, position: 0, chips: 1000)], heroSeatID: 0,
                                    heroCards: [c(.ace, .spades), c(.king, .spades), c(.ten, .hearts), c(.five, .clubs)])
        state = OmahaTableReducer.reduce(state, .playerActed(seatID: 0, action: .folded))
        XCTAssertNil(state.heroCards)
        XCTAssertTrue(state.seat(0)?.isFolded ?? false)
    }

    func testStakesEscalationRaisesBlindsAndFlagsBanner() {
        var state = OmahaTableState(smallBlind: 25, bigBlind: 50)
        state = OmahaTableReducer.reduce(state, .stakesEscalated(smallBlind: 50, bigBlind: 100, level: 1))
        XCTAssertEqual(state.smallBlind, 50)
        XCTAssertEqual(state.bigBlind, 100)
        XCTAssertTrue(state.escalated)
        // A new hand clears the transient banner.
        state = OmahaTableReducer.reduce(state, .handBegan(handNumber: 1, buttonPosition: 1, buttonSeatID: 1,
                                                           smallBlindSeatID: 0, bigBlindSeatID: 1, smallBlind: 50,
                                                           bigBlind: 100, seats: []))
        XCTAssertFalse(state.escalated)
    }

    func testHandEndedSetsFinalChipsAndBoard() {
        var state = OmahaTableState(seats: [OmahaSeatPresentation(id: 0, position: 0, chips: 500)], heroSeatID: 0)
        let board = [c(.two, .diamonds), c(.seven, .clubs), c(.queen, .hearts), c(.nine, .spades), c(.three, .clubs)]
        state = OmahaTableReducer.reduce(state, .handEnded(handNumber: 0, wentToShowdown: true, board: board,
                                                           payouts: [0: 200], chips: [0: 700]))
        XCTAssertEqual(state.seat(0)?.chips, 700)
        XCTAssertEqual(state.board, board)
    }
}
