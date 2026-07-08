// NavigationUITests.swift
// =====================================================================
// XCUITest for the M2.1 world navigation (D-035): the app opens on Home, the
// Riverwood is enterable and lists its three tables, the Five-Card Draw slot is
// visible but not enterable, Settings is on every screen, and the App VoiceOver
// mode switch keeps its state across screens.

import XCTest

final class NavigationUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-resetWallet"]   // fresh 5000 chips
        app.launch()
        return app
    }

    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    func testOpensOnHomeAndEntersRiverwoodTableList() {
        let app = launch()

        // Home: title, settings, chips balance.
        XCTAssertTrue(app.staticTexts["home.title"].waitForExistence(timeout: 15), "did not open on Home")
        XCTAssertTrue(app.buttons["settings.button"].exists, "settings missing on Home")
        XCTAssertTrue(app.staticTexts["chrome.chips"].exists, "chips balance missing on Home")

        // Enter the Riverwood.
        let riverwood = app.buttons["home.casino.riverwood"]
        XCTAssertTrue(riverwood.exists, "Riverwood entry missing")
        riverwood.tap()

        // Its three tables: Classic + Fast are buttons; the Five-Card Draw is a
        // visible-but-not-enterable slot (present as an element, not a button).
        XCTAssertTrue(app.buttons["riverwood.table.classic"].waitForExistence(timeout: 10), "Classic table missing")
        XCTAssertTrue(app.buttons["riverwood.table.fast"].exists, "Fast table missing")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "riverwood.table.draw").firstMatch.exists,
                      "Five-Card Draw slot missing")
        XCTAssertFalse(app.buttons["riverwood.table.draw"].exists, "Five-Card Draw must not be enterable")

        // Settings present here too; back returns to Home.
        XCTAssertTrue(app.buttons["settings.button"].exists, "settings missing in Riverwood")
        app.buttons["chrome.back"].tap()
        XCTAssertTrue(app.buttons["home.casino.riverwood"].waitForExistence(timeout: 5), "did not return to Home")
    }

    func testVoiceOverModeSwitchKeepsStateAcrossScreens() {
        let app = launch()

        // Toggle it on Home.
        app.buttons["settings.button"].tap()
        let toggle = app.switches["settings.vomode.switch"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let initial = toggle.value as? String
        flip(toggle)
        let deadline = Date().addingTimeInterval(3)
        while (toggle.value as? String) == initial && Date() < deadline { usleep(150_000) }
        let flipped = toggle.value as? String
        XCTAssertNotEqual(initial, flipped, "the switch did not change")
        app.buttons["settings.done"].tap()

        // Navigate to the Riverwood and reopen settings — state is kept.
        app.buttons["home.casino.riverwood"].tap()
        XCTAssertTrue(app.buttons["settings.button"].waitForExistence(timeout: 5))
        app.buttons["settings.button"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, flipped, "the switch state was not kept across screens")

        // Leave it as found.
        if toggle.value as? String != initial { flip(toggle) }
        app.buttons["settings.done"].tap()
    }
}
