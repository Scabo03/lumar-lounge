import XCTest
@testable import UI
import GameWorld

/// The app-level wallet + navigation wrapper (D-035/D-036).
@MainActor
final class AppStateTests: XCTestCase {

    private final class MemStore: ChipsStore {
        var value: Int?
        func loadChips() -> Int? { value }
        func saveChips(_ chips: Int) { value = chips }
    }
    private func app(startingChips: Int? = nil) -> AppState {
        let store = MemStore(); store.value = startingChips
        return AppState(account: PlayerAccount(store: store))
    }

    func testSitDownDeductsBuyInAndNavigatesToTheTable() {
        let state = app()                       // 5000
        let stack = state.sitDown(.classic, buyIn: 1000)
        XCTAssertEqual(stack, 1000)
        XCTAssertEqual(state.chips, 4000)
        XCTAssertEqual(state.screen, .table(.classic))
    }

    func testSitDownFailsAndStaysPutWhenTooPoor() {
        let state = app(startingChips: 500)
        XCTAssertFalse(state.canAfford(1000))
        XCTAssertNil(state.sitDown(.classic, buyIn: 1000))
        XCTAssertEqual(state.chips, 500)
        XCTAssertEqual(state.screen, .home)
    }

    func testLeavingCreditsRemainingAndReturnsToRiverwood() {
        let state = app()
        state.sitDown(.fast, buyIn: 1000)       // 4000
        state.leaveTable(cashingOut: 1600)      // won at the table → 5600
        XCTAssertEqual(state.chips, 5600)
        XCTAssertEqual(state.screen, .riverwood)
    }

    func testBustReturnsToRiverwoodWithNoCredit() {
        let state = app()
        state.sitDown(.classic, buyIn: 1000)    // 4000
        state.leaveTable(cashingOut: 0)         // busted
        XCTAssertEqual(state.chips, 4000)
        XCTAssertEqual(state.screen, .riverwood)
    }

    // MARK: - Five-Card Draw table (D-044)

    func testSitDownDrawDeductsBuyInAndNavigates() {
        let state = app()                       // 5000
        let stack = state.sitDownDraw(buyIn: 2000)
        XCTAssertEqual(stack, 2000)
        XCTAssertEqual(state.chips, 3000)
        XCTAssertEqual(state.screen, .drawTable)
    }

    func testSitDownDrawFailsWhenTooPoor() {
        let state = app(startingChips: 1500)
        XCTAssertFalse(state.canAfford(2000))
        XCTAssertNil(state.sitDownDraw(buyIn: 2000))
        XCTAssertEqual(state.chips, 1500)
        XCTAssertEqual(state.screen, .home)
    }

    func testLeavingDrawTableCreditsRemainingAndReturns() {
        let state = app()
        state.sitDownDraw(buyIn: 2000)          // 3000
        state.leaveTable(cashingOut: 2600)      // won at the draw table → 5600
        XCTAssertEqual(state.chips, 5600)
        XCTAssertEqual(state.screen, .riverwood)
    }
}
