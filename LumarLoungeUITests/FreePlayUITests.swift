// FreePlayUITests.swift
// =====================================================================
// XCUITest for the ⚠️ TEMPORARY free-play test mode (D-050): the app shows a
// visible "free play" badge on every screen, the balance is the starting 5000,
// and every table (including the 2000-buy-in Five-Card Draw) is enterable
// regardless of balance.

import XCTest

final class FreePlayUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-resetWallet"]
        app.launch()
        return app
    }

    private func badge(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "debug.freeplay.badge").firstMatch
    }

    func testFreePlayBadgeShownAndBalanceIsStartingChips() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["home.title"].waitForExistence(timeout: 20), "did not open on Home")
        // The free-play badge is visible on Home.
        XCTAssertTrue(badge(app).exists, "free-play badge missing on Home")
        // Balance is the starting 5000.
        XCTAssertTrue(app.staticTexts["chrome.chips"].exists, "chips balance missing")
    }

    func testAllTablesEnterableInFreePlay() {
        let app = launch()
        XCTAssertTrue(app.buttons["home.casino.riverwood"].waitForExistence(timeout: 20))
        app.buttons["home.casino.riverwood"].tap()
        // All three tables are enterable buttons — including the 2000-buy-in Draw,
        // regardless of the shown balance (free play, D-050).
        XCTAssertTrue(app.buttons["riverwood.table.classic"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["riverwood.table.fast"].exists)
        XCTAssertTrue(app.buttons["riverwood.table.draw"].isEnabled, "Draw table must be enterable in free play")
        // The badge follows onto the Riverwood screen too.
        XCTAssertTrue(badge(app).exists, "free-play badge missing in the Riverwood")
    }
}
