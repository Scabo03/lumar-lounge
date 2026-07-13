// SkypoolUITests.swift
// =====================================================================
// XCUITest for the Skypool Casino and its Omaha "Marble" table (D-065/D-066): Home
// lists the Skypool, the Skypool lists its three tables (Fast, Classic, Marble), and
// the Marble table opens onto an accessible Omaha table (container, board, pot, the
// hero's four cards, the action bar, the leave control).
//
// Free-play mode is on in this build, so every table is enterable regardless of the
// buy-in (the buy-in logic is unit-tested separately in CasinoTests with free-play off).

import XCTest

final class SkypoolUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-resetWallet", "-uiTesting"]
        app.launch()
        return app
    }

    func testHomeListsSkypoolAndItsThreeTables() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["home.title"].waitForExistence(timeout: 15), "did not open on Home")

        let skypool = app.buttons["home.casino.skypool"]
        XCTAssertTrue(skypool.waitForExistence(timeout: 5), "Skypool entry missing on Home")
        skypool.tap()

        XCTAssertTrue(app.buttons["skypool.table.fast"].waitForExistence(timeout: 10), "Skypool Fast missing")
        XCTAssertTrue(app.buttons["skypool.table.classic"].exists, "Skypool Classic missing")
        XCTAssertTrue(app.buttons["skypool.table.marble"].exists, "Skypool Marble (Omaha) missing")

        // Settings present here too; back returns to Home.
        XCTAssertTrue(app.buttons["settings.button"].exists, "settings missing in Skypool")
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.casino.skypool"].waitForExistence(timeout: 5), "did not return to Home")
    }

    func testMarbleOpensAnAccessibleOmahaTable() {
        let app = launch()
        XCTAssertTrue(app.buttons["home.casino.skypool"].waitForExistence(timeout: 15))
        app.buttons["home.casino.skypool"].tap()

        let marble = app.buttons["skypool.table.marble"]
        XCTAssertTrue(marble.waitForExistence(timeout: 10))
        marble.tap()

        // The Omaha table renders with its accessible elements.
        XCTAssertTrue(app.otherElements["omahatable.container"].waitForExistence(timeout: 15),
                      "Omaha table container missing")
        XCTAssertTrue(app.staticTexts["omahatable.pot"].exists, "pot missing")
        XCTAssertTrue(app.otherElements["omahatable.board"].exists || app.staticTexts["omahatable.board"].exists,
                      "board missing")
        // The action bar is present (buttons active only on the human's turn).
        XCTAssertTrue(app.buttons["action.raise"].exists, "raise button missing")
        XCTAssertTrue(app.buttons["action.fold"].exists, "fold button missing")
        XCTAssertTrue(app.buttons["action.checkcall"].exists, "check/call button missing")
        // The leave control is present.
        XCTAssertTrue(app.buttons["table.leave"].exists, "leave control missing")
    }
}
