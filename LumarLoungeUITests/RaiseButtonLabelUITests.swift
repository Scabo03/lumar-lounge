// RaiseButtonLabelUITests.swift
// =====================================================================
// Runtime guard for the two Raise buttons' VoiceOver labels (D-059). The pronunciation
// itself (IPA) is pinned by PokerSpeechTests; here we lock the WIRING: both buttons
// must actually apply the phonetic accessibility label at runtime (not fall back to
// the visible English "Raise", which the Italian voice reads "ace"). XCUITest's
// `.label` returns the label's plain text, so we assert its base text is the phonetic
// form — catching the "one call-site wired, the other raw" and "label not applied"
// regressions on the real accessibility tree.

import XCTest

final class RaiseButtonLabelUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func testTexasRaiseButtonHasPhoneticLabel() {
        let app = XCUIApplication()
        app.launchArguments += ["-resetWallet"]
        app.launch()
        app.buttons["home.casino.riverwood"].tap()
        let classic = app.buttons["riverwood.table.classic"]
        XCTAssertTrue(classic.waitForExistence(timeout: 15))
        classic.tap()
        let raise = app.buttons["action.raise"]
        XCTAssertTrue(raise.waitForExistence(timeout: 20))
        XCTAssertEqual(raise.label, "reis",
                       "the Texas Raise button must read the phonetic label, not the English 'Raise'")
    }

    func testDrawRaiseButtonHasPhoneticLabel() {
        let app = XCUIApplication()
        app.launchArguments += ["-resetWallet"]
        app.launch()
        app.buttons["home.casino.riverwood"].tap()
        let draw = app.buttons["riverwood.table.draw"]
        XCTAssertTrue(draw.waitForExistence(timeout: 15))
        draw.tap()
        let raise = app.buttons["action.raise"]
        XCTAssertTrue(raise.waitForExistence(timeout: 20))
        XCTAssertTrue(raise.label.hasPrefix("reis"),
                      "the Draw Raise button must read the phonetic 'reis …', got '\(raise.label)'")
    }
}
