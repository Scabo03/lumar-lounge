// TableAccessibilityUITests.swift
// =====================================================================
// XCUITests for the playable table (M1.7): the layered layout exists and is
// accessible; the action buttons are active on the human's turn and disabled on
// a bot's turn; the Raise box opens with its four controls plus confirm/cancel
// and closes again; and a minimal play proceeds end-to-end (the human takes an
// action and the session continues).
//
// Uses normal pacing (deterministic fixed seed) with generous waits, so the
// enabled/disabled windows are long enough to observe reliably.

import XCTest

final class TableAccessibilityUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitEnabled(_ element: XCUIElement, _ timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isEnabled && element.isHittable { return true }
            usleep(200_000)
        }
        return false
    }

    private func waitDisabled(_ element: XCUIElement, _ timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && !element.isEnabled { return true }
            usleep(200_000)
        }
        return false
    }

    func testLayoutAndHumanInteraction() {
        let app = XCUIApplication()
        app.launchArguments += ["-resetWallet"]   // deterministic fresh 5000 chips (M2.1)
        app.launch()

        // 0. Navigate Home → Riverwood → Classic table (the app no longer opens on
        // the table directly — D-035).
        let riverwood = app.buttons["home.casino.riverwood"]
        XCTAssertTrue(riverwood.waitForExistence(timeout: 15), "Riverwood entry missing on Home")
        riverwood.tap()
        let classicTable = app.buttons["riverwood.table.classic"]
        XCTAssertTrue(classicTable.waitForExistence(timeout: 10), "Classic table missing in Riverwood")
        classicTable.tap()

        // 1. The layered layout is present and accessible (leaves of each zone).
        XCTAssertTrue(any(app, "table.container").waitForExistence(timeout: 15), "table missing")
        XCTAssertTrue(any(app, "table.board").waitForExistence(timeout: 5), "board missing")
        XCTAssertTrue(any(app, "table.pot").waitForExistence(timeout: 5), "pot missing")
        // Opponents zone: the three bot badges.
        XCTAssertTrue(any(app, "opponent.1").waitForExistence(timeout: 5), "opponent 1 missing")
        XCTAssertTrue(any(app, "opponent.2").exists, "opponent 2 missing")
        XCTAssertTrue(any(app, "opponent.3").exists, "opponent 3 missing")
        // Human zone: the hero's cards.
        XCTAssertTrue(any(app, "hero.cards").waitForExistence(timeout: 15), "hero cards missing")
        // Action zone: the three action buttons.
        XCTAssertTrue(app.buttons["action.checkcall"].exists, "check/call missing")
        XCTAssertTrue(app.buttons["action.fold"].exists, "fold missing")
        XCTAssertTrue(app.buttons["action.raise"].exists, "raise missing")

        // 2. On the human's turn the action buttons are active.
        let checkCall = app.buttons["action.checkcall"]
        let fold = app.buttons["action.fold"]
        let raise = app.buttons["action.raise"]
        XCTAssertTrue(waitEnabled(checkCall, 20), "Check/Call not active on the human's turn")
        XCTAssertTrue(fold.isEnabled, "Fold should be active on the human's turn")
        XCTAssertTrue(raise.isEnabled, "Raise should be active on the human's turn")

        // 3. The Raise box opens, holds its four controls + confirm/cancel, closes.
        raise.tap()
        XCTAssertTrue(any(app, "raisebox").waitForExistence(timeout: 5), "raise box did not open")
        XCTAssertTrue(app.buttons["raise.minus"].exists)
        XCTAssertTrue(any(app, "raise.value").exists)
        XCTAssertTrue(app.buttons["raise.plus"].exists)
        XCTAssertTrue(app.buttons["raise.allin"].exists)
        XCTAssertTrue(app.buttons["raise.confirm"].exists)
        XCTAssertTrue(app.buttons["raise.cancel"].exists)
        app.buttons["raise.plus"].tap()
        app.buttons["raise.plus"].tap()
        app.buttons["raise.cancel"].tap()
        XCTAssertFalse(any(app, "raisebox").waitForExistence(timeout: 2), "raise box did not close")

        // 4. The human acts (check/call); the buttons then dim on the bots' turn.
        XCTAssertTrue(checkCall.isEnabled)
        checkCall.tap()
        XCTAssertTrue(waitDisabled(checkCall, 10), "buttons should dim on a bot's turn")

        // 5. The session continues (the human is dealt back in on a later street).
        XCTAssertTrue(waitEnabled(checkCall, 30) || any(app, "endgame.message").exists,
                      "the session did not continue to another human turn")
    }
}
