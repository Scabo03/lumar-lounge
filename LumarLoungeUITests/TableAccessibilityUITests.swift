// TableAccessibilityUITests.swift
// =====================================================================
// A minimal XCUITest that launches the demo table and verifies the core
// accessibility structure is in place — every main element exists and is
// reachable by its accessibility identifier (M1.6). It does not test the game
// evolving over time (that belongs to later, interaction-driven bricks); it
// asserts the accessibility scaffolding stands.

import XCTest

final class TableAccessibilityUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Finds an element by identifier regardless of its resolved element type
    /// (SwiftUI may expose a labelled element as static text or a generic one).
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testTableAccessibilityStructureExists() {
        let app = XCUIApplication()
        // Keep the table static so the accessibility tree is stable to inspect.
        app.launchArguments = ["-uiTesting"]
        app.launch()

        // The table container appears.
        XCTAssertTrue(element(app, "table.container").waitForExistence(timeout: 15),
                      "The table container is not accessible")

        // The three seats are present and accessible.
        for id in 0..<3 {
            XCTAssertTrue(element(app, "seat.\(id)").waitForExistence(timeout: 15),
                          "Seat \(id) is not accessible")
        }

        // Board, pot and button indicator are present.
        XCTAssertTrue(element(app, "table.board").waitForExistence(timeout: 15),
                      "The board area is not accessible")
        XCTAssertTrue(element(app, "table.pot").waitForExistence(timeout: 15),
                      "The pot indicator is not accessible")
        XCTAssertTrue(element(app, "table.button").waitForExistence(timeout: 15),
                      "The button indicator is not accessible")
    }
}
