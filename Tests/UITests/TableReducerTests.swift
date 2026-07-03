import XCTest
@testable import UI
import GameWorld
import GameEngine

/// Pure tests of the presentation-state reduction (no SwiftUI, no localization).
final class TableReducerTests: XCTestCase {

    private func snap(_ id: Int, _ pos: Int, _ chips: Int) -> SeatSnapshot {
        SeatSnapshot(seatID: id, position: pos, chips: chips)
    }

    private func started() -> TableState {
        TableReducer.reduce(.empty, .sessionBegan(seats: [snap(0, 0, 1000), snap(1, 1, 1000), snap(2, 2, 1000)],
                                                  smallBlind: 10, bigBlind: 20))
    }

    func testSessionBeganSeatsThePlayers() {
        let state = started()
        XCTAssertEqual(state.seats.map { $0.id }, [0, 1, 2])
        XCTAssertEqual(state.seats.map { $0.chips }, [1000, 1000, 1000])
        XCTAssertEqual(state.phase, .playing)
    }

    func testHandBeganSetsButtonAndResetsBoardAndPot() {
        var state = started()
        state.board = [Card(.ace, .spades)]
        state.pot = 999
        state = TableReducer.reduce(state, .handBegan(handNumber: 0, buttonPosition: 0, buttonSeatID: 0,
                                                      smallBlindSeatID: 1, bigBlindSeatID: 2,
                                                      smallBlind: 10, bigBlind: 20,
                                                      seats: [snap(0, 0, 1000), snap(1, 1, 1000), snap(2, 2, 1000)]))
        XCTAssertEqual(state.board, [])
        XCTAssertEqual(state.pot, 0)
        XCTAssertEqual(state.buttonSeatID, 0)
        XCTAssertEqual(state.smallBlindSeatID, 1)
        XCTAssertEqual(state.bigBlindSeatID, 2)
        XCTAssertTrue(state.seat(0)!.isButton)
        XCTAssertFalse(state.seat(1)!.isButton)
    }

    func testBlindPostedMovesChipsIntoThePot() {
        var state = started()
        state = TableReducer.reduce(state, .blindPosted(seatID: 1, blind: .small, amount: 10, isAllIn: false))
        state = TableReducer.reduce(state, .blindPosted(seatID: 2, blind: .big, amount: 20, isAllIn: false))
        XCTAssertEqual(state.seat(1)!.chips, 990)
        XCTAssertEqual(state.seat(2)!.chips, 980)
        XCTAssertEqual(state.pot, 30)
    }

    func testRaiseCommitsChipsAndRecordsLastAction() {
        var state = started()
        state = TableReducer.reduce(state, .playerActed(seatID: 0, action: .raised(to: 60, amount: 60, isAllIn: false)))
        XCTAssertEqual(state.seat(0)!.chips, 940)
        XCTAssertEqual(state.pot, 60)
        XCTAssertEqual(state.lastAction, LastAction(seatID: 0, action: .raised(to: 60, amount: 60, isAllIn: false)))
    }

    func testFoldMarksSeatAndDropsCards() {
        var state = started()
        state = TableReducer.reduce(state, .holeCardsDealt(seatID: 0))
        XCTAssertTrue(state.seat(0)!.hasCards)
        state = TableReducer.reduce(state, .playerActed(seatID: 0, action: .folded))
        XCTAssertTrue(state.seat(0)!.isFolded)
        XCTAssertFalse(state.seat(0)!.hasCards)
    }

    func testAllInCallSetsAllInFlag() {
        var state = started()
        state = TableReducer.reduce(state, .playerActed(seatID: 1, action: .called(amount: 1000, isAllIn: true)))
        XCTAssertTrue(state.seat(1)!.isAllIn)
        XCTAssertEqual(state.pot, 1000)
    }

    func testStreetOpenedAppendsBoard() {
        var state = started()
        let flop = [Card(.ace, .spades), Card(.king, .hearts), Card(.two, .clubs)]
        state = TableReducer.reduce(state, .streetOpened(street: .flop, communityCards: flop))
        state = TableReducer.reduce(state, .streetOpened(street: .turn, communityCards: [Card(.five, .diamonds)]))
        XCTAssertEqual(state.board.count, 4)
        XCTAssertEqual(state.lastStreet, .turn)
    }

    func testHandShownRevealsSeatCards() {
        var state = started()
        let hole = [Card(.ace, .spades), Card(.ace, .hearts)]
        state = TableReducer.reduce(state, .handShown(seatID: 2, holeCards: hole, category: .pair, bestFive: hole))
        XCTAssertEqual(state.seat(2)!.revealedHole, hole)
    }

    func testHandEndedOverridesChips() {
        var state = started()
        state = TableReducer.reduce(state, .handEnded(handNumber: 0, wentToShowdown: true, board: [],
                                                      payouts: [0: 60], chips: [0: 1060, 1: 990, 2: 950]))
        XCTAssertEqual(state.seat(0)!.chips, 1060)
        XCTAssertEqual(state.seat(2)!.chips, 950)
    }

    func testBustAndSessionEndSetWinner() {
        var state = started()
        state = TableReducer.reduce(state, .handEnded(handNumber: 0, wentToShowdown: true, board: [],
                                                      payouts: [:], chips: [0: 0, 1: 0, 2: 3000]))
        state = TableReducer.reduce(state, .playerBusted(playerID: 0))
        state = TableReducer.reduce(state, .playerBusted(playerID: 1))
        XCTAssertTrue(state.seat(0)!.isBusted)
        state = TableReducer.reduce(state, .sessionEnded(reason: .notEnoughPlayers))
        XCTAssertEqual(state.phase, .finished)
        XCTAssertEqual(state.winnerSeatID, 2)
    }
}
