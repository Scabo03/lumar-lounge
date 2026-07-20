// FocusHandoffTests.swift
// =====================================================================
// D-092: an element that vanishes as the result of an action must declare
// where VoiceOver focus goes.
//
// `voiceOverFocusLanding()` (D-057) covers APPEARANCE, and that is all it can
// cover: it hangs off `onAppear`. Every table in the project presents its
// modal boxes OVER content that is never removed from the tree — only
// `accessibilityHidden` — so when the box closes nothing appears, nothing
// re-fires, and the cursor is left on a button that no longer exists. These
// are source guards: what they protect is structural (a declared hand-off on
// every dismissal path), and structure is exactly what a static check can see.

import XCTest
@testable import UI

final class FocusHandoffTests: XCTestCase {

    private func source(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("UI/\(name)"), encoding: .utf8)
    }

    /// Every view model that owns a modal box bumps a focus token when it closes —
    /// and does it in the property's `didSet`, so no dismissal path (confirm,
    /// cancel, tap on the scrim) can be added later that forgets to.
    func testEveryModalOwningViewModelDeclaresAFocusHandOffOnDismissal() throws {
        let models = ["TableViewModel.swift", "OmahaTableViewModel.swift",
                      "StudTableViewModel.swift", "DrawTableViewModel.swift",
                      "MachiavelliTableViewModel.swift"]
        for name in models {
            let src = try source(name)
            XCTAssertTrue(src.contains("focusReturnToken += 1"),
                          "\(name) must hand focus on when its box closes.")
            XCTAssertTrue(src.contains("didSet"),
                          "\(name) must bump it in didSet, so EVERY dismissal path is covered.")
        }
    }

    /// …and every table has an element that claims that focus back.
    func testEveryTableHasAFocusDestinationForADismissedBox() throws {
        let views = ["HeroZoneView.swift", "OmahaTableView.swift", "StudTableView.swift",
                     "DrawTableView.swift", "MachiavelliTableView.swift"]
        for name in views {
            XCTAssertTrue(try source(name).contains("voiceOverFocusClaim(onChangeOf:"),
                          "\(name) must claim focus back when a box closes.")
        }
    }

    /// Blackjack is the other shape, and the one the player feels most: the wager
    /// box opens EVERY round, so the stranding happens every round. There the
    /// destination is newly inserted (the hand is dealt after the box closes), so
    /// the claim is the appearance form, on the FIRST hand only — a split must not
    /// snatch the cursor off a hand still being played.
    func testBlackjackLandsOnTheDealtHandAfterTheWagerBoxCloses() throws {
        let src = try source("BlackjackTableView.swift")
        XCTAssertTrue(src.contains(".voiceOverFocusClaim(index == 0)"),
                      "The dealt hand must claim focus, and only the first hand.")

        // And the destination is the HAND, not the dealer or the stakes: it leads
        // with the total, which is the information the wager was just chosen for.
        let handRange = try XCTUnwrap(src.range(of: "private func handView"))
        let claimRange = try XCTUnwrap(src.range(of: ".voiceOverFocusClaim(index == 0)"))
        XCTAssertLessThan(handRange.lowerBound, claimRange.lowerBound,
                          "The claim belongs to the player's hand element.")
    }

    /// A modal dismissal is not a screen change, so it must not be announced as
    /// one — a `.screenChanged` here would re-scan and re-announce the whole table
    /// every single hand.
    func testTheHandOffIsALayoutChangeNotAScreenChange() throws {
        let src = try source("FocusLanding.swift")
        XCTAssertTrue(src.contains("postLayoutChanged()"),
                      "The return path posts a layout change.")

        // And posting still happens in exactly one file (D-032).
        let queue = try source("AnnouncementQueue.swift")
        XCTAssertTrue(queue.contains("UIAccessibility.post(notification: .layoutChanged"),
                      "The new post lives with the others, in the queue.")
    }
}
