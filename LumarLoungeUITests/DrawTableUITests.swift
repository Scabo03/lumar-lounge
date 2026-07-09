// DrawTableUITests.swift
// =====================================================================
// XCUITest for the playable Five-Card Draw table (D-044): entering from the
// Riverwood's Sala Whiskey, the accessible layout (five hero cards, pot, action
// bar), and the modal draw box opening at draw time with selectable cards and an
// always-active Confirm that dismisses it.
//
// The app launches with -uiTesting (fast pacing) so the bot turns resolve quickly
// and the session pauses at the human's decision points.

import XCTest

final class DrawTableUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launchAtDrawTable() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-resetWallet", "-uiTesting"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.title"].waitForExistence(timeout: 20), "did not open on Home")
        app.buttons["home.casino.riverwood"].tap()
        let draw = app.buttons["riverwood.table.draw"]
        XCTAssertTrue(draw.waitForExistence(timeout: 10), "Five-Card Draw table not enterable")
        draw.tap()
        return app
    }

    func testEntersDrawTableAndShowsAccessibleLayout() {
        let app = launchAtDrawTable()
        // The table centre (pot) and the human's five cards appear.
        XCTAssertTrue(app.otherElements["drawtable.pot"].waitForExistence(timeout: 15)
                      || app.staticTexts["drawtable.pot"].waitForExistence(timeout: 1),
                      "pot indicator missing")
        XCTAssertTrue(app.otherElements["hero.cards"].waitForExistence(timeout: 15)
                      || app.staticTexts["hero.cards"].exists, "hero cards missing")
        // The leave-table control is present.
        XCTAssertTrue(app.buttons["table.leave"].exists, "leave-table control missing")
        // Settings chrome is present here too.
        XCTAssertTrue(app.buttons["settings.button"].exists, "settings missing at the draw table")
    }

    /// Drives the hand (opening the pot when possible to force a played deal to the
    /// draw, otherwise checking/calling) until the human's draw box appears.
    private func driveToDrawBox(_ app: XCUIApplication) {
        let box = app.otherElements["drawbox"]
        let bet = app.buttons["action.bet"]
        let checkCall = app.buttons["action.checkcall"]
        let deadline = Date().addingTimeInterval(60)
        while !box.exists && Date() < deadline {
            if bet.exists && bet.isEnabled {
                bet.tap()
            } else if checkCall.exists && checkCall.isEnabled {
                checkCall.tap()
            } else {
                usleep(200_000)
            }
        }
        XCTAssertTrue(box.waitForExistence(timeout: 5), "the draw box never opened")
    }

    func testDrawBoxOpensSelectsAndConfirms() {
        let app = launchAtDrawTable()
        driveToDrawBox(app)

        // Five selectable cards, a count, and an always-active Confirm.
        for i in 0..<5 {
            XCTAssertTrue(app.buttons["draw.card.\(i)"].exists, "draw card \(i) missing")
        }
        let confirm = app.buttons["draw.confirm"]
        XCTAssertTrue(confirm.exists && confirm.isEnabled, "confirm missing or disabled")

        // Select a card, then confirm — the box dismisses and play resumes.
        app.buttons["draw.card.0"].tap()
        confirm.tap()
        XCTAssertTrue(waitForDisappearance(of: app.otherElements["drawbox"], timeout: 10),
                      "the draw box did not dismiss on confirm")
    }

    /// Fix 2 (D-046): selecting/deselecting a card updates its state but never
    /// removes or re-orders elements — every card, the count and Confirm stay
    /// reachable in a stable order (the precondition for fluid VoiceOver swipe
    /// navigation, which a headless XCUITest can't drive directly).
    func testDrawBoxStaysFullyNavigableAcrossSelections() {
        let app = launchAtDrawTable()
        driveToDrawBox(app)

        let cards = (0..<5).map { app.buttons["draw.card.\($0)"] }
        let count = app.staticTexts["draw.box.count"]
        let confirm = app.buttons["draw.confirm"]

        func assertAllReachable(_ context: String) {
            for (i, card) in cards.enumerated() {
                XCTAssertTrue(card.exists && card.isHittable, "card \(i) not reachable \(context)")
            }
            XCTAssertTrue(count.exists, "count not reachable \(context)")
            XCTAssertTrue(confirm.exists && confirm.isEnabled, "confirm not reachable \(context)")
        }

        assertAllReachable("initially")
        // Select two, deselect one — after every toggle the whole grid is intact
        // and no element has disappeared or become unhittable.
        cards[0].tap(); assertAllReachable("after selecting card 0")
        cards[2].tap(); assertAllReachable("after selecting card 2")
        cards[0].tap(); assertAllReachable("after deselecting card 0")
        // The identifiers are still their original positions (no re-ordering).
        for i in 0..<5 { XCTAssertTrue(cards[i].exists, "card \(i) lost its identity") }

        confirm.tap()
        XCTAssertTrue(waitForDisappearance(of: app.otherElements["drawbox"], timeout: 10),
                      "the draw box did not dismiss on confirm")
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && Date() < deadline { usleep(150_000) }
        return !element.exists
    }
}
