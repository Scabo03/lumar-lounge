import XCTest
@testable import UI
import GameWorld

/// The app-level wallet + navigation wrapper (D-035/D-036, generalised D-065).
@MainActor
final class AppStateTests: XCTestCase {

    private final class MemStore: ChipsStore {
        var value: Int?
        func loadChips() -> Int? { value }
        func saveChips(_ chips: Int) { value = chips }
    }
    private func app(startingChips: Int? = nil) -> AppState {
        let store = MemStore(); store.value = startingChips
        return AppState(account: PlayerAccount(store: store, freePlay: false))
    }

    // Real Riverwood tables — the generalisation must leave their buy-ins unchanged.
    private var classic: CasinoTable { Casinos.riverwood.tables.first { $0.id == "riverwood.table.classic" }! }
    private var fast: CasinoTable { Casinos.riverwood.tables.first { $0.id == "riverwood.table.fast" }! }
    private var draw: CasinoTable { Casinos.riverwood.tables.first { $0.id == "riverwood.table.draw" }! }

    func testRiverwoodBuyInsUnchanged() {
        XCTAssertEqual(classic.buyIn, 1000)
        XCTAssertEqual(fast.buyIn, 1000)
        XCTAssertEqual(draw.buyIn, 2000)
    }

    func testSitDownDeductsBuyInAndNavigatesToTheTable() {
        let state = app()                       // 5000
        state.openCasino(Casinos.riverwood)
        let stack = state.sitDown(classic)
        XCTAssertEqual(stack, 1000)
        XCTAssertEqual(state.chips, 4000)
        XCTAssertEqual(state.screen, .table(classic))
    }

    func testSitDownFailsAndStaysPutWhenTooPoor() {
        let state = app(startingChips: 500)
        state.openCasino(Casinos.riverwood)
        XCTAssertFalse(state.canAfford(1000))
        XCTAssertNil(state.sitDown(classic))
        XCTAssertEqual(state.chips, 500)
        XCTAssertEqual(state.screen, .casino(Casinos.riverwood))
    }

    func testLeavingCreditsRemainingAndReturnsToTheCasino() {
        let state = app()
        state.openCasino(Casinos.riverwood)
        state.sitDown(fast)                     // 4000
        state.leaveTable(cashingOut: 1600)      // won at the table → 5600
        XCTAssertEqual(state.chips, 5600)
        XCTAssertEqual(state.screen, .casino(Casinos.riverwood))
    }

    func testBustReturnsToTheCasinoWithNoCredit() {
        let state = app()
        state.openCasino(Casinos.riverwood)
        state.sitDown(classic)                  // 4000
        state.leaveTable(cashingOut: 0)         // busted
        XCTAssertEqual(state.chips, 4000)
        XCTAssertEqual(state.screen, .casino(Casinos.riverwood))
    }

    // MARK: - Five-Card Draw table (D-044)

    func testSitDownDrawDeductsBuyInAndNavigates() {
        let state = app()                       // 5000
        state.openCasino(Casinos.riverwood)
        let stack = state.sitDown(draw)
        XCTAssertEqual(stack, 2000)
        XCTAssertEqual(state.chips, 3000)
        XCTAssertEqual(state.screen, .table(draw))
    }

    func testSitDownDrawFailsWhenTooPoor() {
        let state = app(startingChips: 1500)
        state.openCasino(Casinos.riverwood)
        XCTAssertFalse(state.canAfford(2000))
        XCTAssertNil(state.sitDown(draw))
        XCTAssertEqual(state.chips, 1500)
        XCTAssertEqual(state.screen, .casino(Casinos.riverwood))
    }

    func testLeavingDrawTableCreditsRemainingAndReturns() {
        let state = app()
        state.openCasino(Casinos.riverwood)
        state.sitDown(draw)                     // 3000
        state.leaveTable(cashingOut: 2600)      // won at the draw table → 5600
        XCTAssertEqual(state.chips, 5600)
        XCTAssertEqual(state.screen, .casino(Casinos.riverwood))
    }
}
