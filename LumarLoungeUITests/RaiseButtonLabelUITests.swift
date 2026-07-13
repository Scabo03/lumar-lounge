// RaiseButtonLabelUITests.swift
// =====================================================================
// Runtime guard for the Raise and Fold buttons' VoiceOver labels (D-060). The correct
// SOUND was chosen by ear (D-060); this locks the WIRING at runtime so the app can't
// regress to a label that isn't the ear-verified one. XCUITest's `.label` returns the
// accessibility label's plain text, which is exactly the ear-verified plain grapheme
// (no IPA), so we can assert it directly on the real accessibility tree — for BOTH
// call-sites (Texas + Draw), the "one wired, the other raw" regression too.

import XCTest

final class RaiseButtonLabelUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func enter(_ tableIdentifier: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-resetWallet"]
        app.launch()
        app.buttons["home.casino.riverwood"].tap()
        let table = app.buttons[tableIdentifier]
        XCTAssertTrue(table.waitForExistence(timeout: 15), "\(tableIdentifier) missing")
        table.tap()
        return app
    }

    func testTexasRaiseAndFoldLabels() {
        let app = enter("riverwood.table.classic")
        let raise = app.buttons["action.raise"]
        let fold = app.buttons["action.fold"]
        XCTAssertTrue(raise.waitForExistence(timeout: 20))
        XCTAssertEqual(raise.label, "Raise", "Texas Raise button must read the ear-verified 'Raise'")
        XCTAssertEqual(fold.label, "fohld", "Texas Fold button must read the ear-verified 'fohld' (/ˈfold/)")
    }

    func testDrawRaiseAndFoldLabels() {
        let app = enter("riverwood.table.draw")
        let raise = app.buttons["action.raise"]
        let fold = app.buttons["action.fold"]
        XCTAssertTrue(raise.waitForExistence(timeout: 20))
        XCTAssertTrue(raise.label.hasPrefix("Raise"), "Draw Raise button must read 'Raise …', got '\(raise.label)'")
        XCTAssertEqual(fold.label, "fohld", "Draw Fold button must read the ear-verified 'fohld'")
    }
}
