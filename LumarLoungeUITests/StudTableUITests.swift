// StudTableUITests.swift
// =====================================================================
// XCUITest for the ClockTower's Seven-Card Stud Pot Limit table (D-077/D-078): the
// ClockTower lists two tables (Machiavelli + Stud), and the Stud table opens onto an
// accessible poker table — the pot, the stakes, the two opponent badges (the on-demand
// exposed-card INTERROGATION), the hero's cards, the action bar, and the leave control.
//
// Free-play mode is on in this build, so the table is enterable regardless of the 3000
// buy-in (the buy-in + house-prize economy is unit-tested separately with free-play off).

import XCTest

final class StudTableUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-resetWallet", "-uiTesting"]
        app.launch()
        return app
    }

    func testClockTowerListsTheStudTable() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["home.title"].waitForExistence(timeout: 15), "did not open on Home")
        let clock = app.buttons["home.casino.clocktower"]
        XCTAssertTrue(clock.waitForExistence(timeout: 5), "ClockTower entry missing on Home")
        clock.tap()

        XCTAssertTrue(app.buttons["clocktower.table.machiavelli"].waitForExistence(timeout: 10), "Machiavelli missing")
        XCTAssertTrue(app.buttons["clocktower.table.stud"].exists, "Seven-Card Stud table missing")
    }

    func testStudTableIsAccessible() {
        let app = launch()
        XCTAssertTrue(app.buttons["home.casino.clocktower"].waitForExistence(timeout: 15))
        app.buttons["home.casino.clocktower"].tap()

        let stud = app.buttons["clocktower.table.stud"]
        XCTAssertTrue(stud.waitForExistence(timeout: 10))
        stud.tap()

        // The Stud table renders with its accessible elements.
        XCTAssertTrue(app.otherElements["studtable.container"].waitForExistence(timeout: 15), "Stud container missing")
        XCTAssertTrue(app.staticTexts["studtable.pot"].exists, "pot missing")
        XCTAssertTrue(app.staticTexts["studtable.stakes"].exists, "stakes missing")
        // The two opponents' badges — the on-demand board interrogation (D-078), now
        // SPLIT into a board element and an identity element (D-083). The board must be
        // its own swipe stop: reading the boards is done many times per hand, so it may
        // never be buried behind name and chips again.
        XCTAssertTrue(app.otherElements["opponent.1"].waitForExistence(timeout: 10), "opponent 1 identity missing")
        XCTAssertTrue(app.otherElements["opponent.2"].exists, "opponent 2 identity missing")
        XCTAssertTrue(app.otherElements["opponent.1.board"].exists, "opponent 1 board is not its own element")
        XCTAssertTrue(app.otherElements["opponent.2.board"].exists, "opponent 2 board is not its own element")
        // The board element must not read chips — that is the whole point of the split.
        XCTAssertFalse(app.otherElements["opponent.1.board"].label.contains("fiches"),
                       "the board element still carries the chips preamble")

        // D-089 — the player's own hand is ONE element read as a continuous whole, and
        // the up/down split lives on its own element beside it (never inside the hand).
        XCTAssertTrue(app.otherElements["hero.cards"].waitForExistence(timeout: 10), "hero hand missing")
        XCTAssertTrue(app.otherElements["hero.board"].exists, "the hero up/down split lost its own element")
        let hand = app.otherElements["hero.cards"].label
        XCTAssertFalse(hand.lowercased().contains("da tutti"),
                       "the hand readout reintroduced the superfluous aside: \(hand)")

        // Nothing may run off the right edge, at any street (D-089).
        let screen = app.windows.element(boundBy: 0).frame
        for identifier in ["opponent.1.board", "opponent.2.board", "hero.cards", "studtable.pot"] {
            let element = app.otherElements[identifier]
            guard element.exists else { continue }
            XCTAssertLessThanOrEqual(element.frame.maxX, screen.maxX + 0.5,
                                     "\(identifier) overflows the right edge of the screen")
            XCTAssertGreaterThanOrEqual(element.frame.minX, screen.minX - 0.5,
                                        "\(identifier) overflows the left edge of the screen")
        }
        // The action bar and leave control.
        XCTAssertTrue(app.buttons["action.raise"].exists, "raise button missing")
        XCTAssertTrue(app.buttons["action.fold"].exists, "fold button missing")
        XCTAssertTrue(app.buttons["action.checkcall"].exists, "check/call button missing")
        XCTAssertTrue(app.buttons["table.leave"].exists, "leave control missing")
    }
}
