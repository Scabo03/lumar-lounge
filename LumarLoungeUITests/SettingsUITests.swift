// SettingsUITests.swift
// =====================================================================
// XCUITest for the permanent Settings chrome (D-033/D-034): the settings button is
// always present, opens a screen with the "App VoiceOver mode" switch, the switch
// toggles, and its state is maintained when the screen is closed and reopened.

import XCTest

final class SettingsUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func testSettingsButtonOpensScreenTogglesSwitchAndKeepsItsState() {
        let app = XCUIApplication()
        app.launch()

        // The settings button is permanent (top-right chrome).
        let settingsButton = app.buttons["settings.button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 15), "settings button missing")
        settingsButton.tap()

        // The screen shows the App VoiceOver mode switch.
        let toggle = app.switches["settings.vomode.switch"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "VoiceOver mode switch missing")
        let initial = toggle.value as? String

        // Toggling changes its state. (A SwiftUI Toggle in a List flips reliably when
        // tapped on the trailing knob area, not always on the element centre.)
        flip(toggle)
        let flipped = waitForValueChange(toggle, from: initial)
        XCTAssertNotEqual(initial, flipped, "the switch did not change state")

        // Close and reopen: the state is maintained.
        app.buttons["settings.done"].tap()
        settingsButton.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, flipped, "the switch state was not maintained")

        // Leave the preference as we found it.
        if toggle.value as? String != initial { flip(toggle); _ = waitForValueChange(toggle, from: flipped) }
        app.buttons["settings.done"].tap()
    }

    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    private func waitForValueChange(_ toggle: XCUIElement, from old: String?) -> String? {
        let deadline = Date().addingTimeInterval(3)
        while (toggle.value as? String) == old && Date() < deadline { usleep(150_000) }
        return toggle.value as? String
    }
}
