// BlackjackRhythmTests.swift
// =====================================================================
// D-096: three things that were each fine on their own and collided on a
// real device.
//
// Blackjack's round is a loop of modal → table → modal, tighter than any
// other table in the project, and every one of these defects was a case of
// two correct mechanisms firing at the same instant and cancelling each
// other out. What is pinned here is the SEQUENCING and the ORDER, because
// that is what was wrong — not the content of any single line.

import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine

final class BlackjackRhythmTests: XCTestCase {

    private func italian<T>(_ body: () -> T) -> T {
        UIStrings.override = BlackjackLocalizedStrings.italian
        defer { UIStrings.override = nil }
        return body()
    }

    // MARK: - The deal is two beats, not one

    /// The player's hand and the dealer's card must not arrive together: focus
    /// lands on the hand and starts reading it, so anything announced at the
    /// same instant is spoken over.
    func testTheDealerRevealWaitsLongEnoughToBeHeardSeparately() {
        XCTAssertGreaterThanOrEqual(BlackjackPacing.dealerRevealDelay, 1.5,
                                    "The hand needs room to be read before the dealer speaks.")
        // …but it is a beat, not a wait: blackjack's whole character is speed.
        XCTAssertLessThanOrEqual(BlackjackPacing.dealerRevealDelay, 4.0,
                                 "A beat, not a pause the player has to sit through.")
    }

    /// The two halves are disjoint — no word is said twice.
    func testTheHandElementAndTheDealLineDoNotSayTheSameThing() {
        italian {
            let hand = BlackjackHandPresentation(cards: [Card(.ace, .spades), Card(.six, .hearts)],
                                                 bet: 20)
            let element = BlackjackReadout.hand(hand, index: 0, handCount: 1)
            let line = BlackjackSpeechMap.text(for: .dealerShows(card: Card(.ten, .clubs)))

            XCTAssertTrue(element.contains("17"), "The element carries the total: \(element)")
            XCTAssertFalse(line.contains("17"), "The line does not repeat it: \(line)")
            XCTAssertTrue(line.lowercased().contains("dieci"),
                          "The line carries what the element cannot: \(line)")
            XCTAssertFalse(element.lowercased().contains("dieci"),
                           "The element says nothing of the dealer: \(element)")
        }
    }

    // MARK: - The reading order is declared

    /// Sort priorities descend in the order the round is played: what you hold,
    /// what it is worth, what you can do. The chrome at the top of the screen
    /// must not sit in the middle of that.
    func testTheReadingOrderGoesFromTheHandToTheMovesWithoutDetour() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent("UI/BlackjackTableView.swift"),
                              encoding: .utf8)
        let bar = try String(contentsOf: root.appendingPathComponent("UI/BlackjackActionBarView.swift"),
                             encoding: .utf8)

        XCTAssertTrue(view.contains(".accessibilitySortPriority(100)"), "dealer leads")
        XCTAssertTrue(view.contains(".accessibilitySortPriority(90 - Double(index))"), "hands next")
        XCTAssertTrue(view.contains(".accessibilitySortPriority(80)"), "then the stack")
        XCTAssertTrue(view.contains(".accessibilitySortPriority(5)"), "leaving the table comes last")

        // Every move carries an explicit place, all of them between the stack
        // and the leave button.
        XCTAssertTrue(bar.contains(".accessibilitySortPriority(sortPriority)"),
                      "the moves declare their place rather than inheriting it")
        for (move, priority) in [("action.hit", 70), ("action.stand", 69), ("action.double", 68),
                                 ("action.split", 67), ("action.surrender", 66)] {
            XCTAssertTrue(bar.contains("identifier: \"\(move)\", sortPriority: \(priority)"),
                          "\(move) must sit between the stack (80) and leaving (5)")
            XCTAssertLessThan(priority, 80, "the moves come after the stack")
            XCTAssertGreaterThan(priority, 5, "…and before leaving the table")
        }
    }

    // MARK: - A round is explained before the next one is offered

    /// The wager box lands focus, and focus landing interrupts speech. So the
    /// box must wait for the closing lines of the round to finish.
    func testTheWagerBoxWaitsForTheRoundToFinishBeingExplained() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: root.appendingPathComponent("UI/BlackjackTableViewModel.swift"),
                               encoding: .utf8)
        let runBet = try XCTUnwrap(model.range(of: "private func runBet"))
        let assign = try XCTUnwrap(model.range(of: "betBox = BlackjackBetBox"))
        let wait = try XCTUnwrap(model.range(of: "await awaitSpokenChannelQuiet()", range: runBet.lowerBound..<assign.lowerBound),
                                 "the box must wait for the spoken channel before it opens")
        XCTAssertLessThan(wait.upperBound, assign.lowerBound)
    }

    /// And what it waits for is a real account of the hand: the dealer's total
    /// (the cause) and the settlement (the effect), neither droppable.
    func testTheEndOfARoundExplainsBothTheCauseAndTheResult() {
        italian {
            let dealer = BlackjackSpeechMap.plan(for: .dealerPlayed(cards: [Card(.ten, .clubs),
                                                                            Card(.nine, .hearts)],
                                                                     total: 19, isSoft: false,
                                                                     didBust: false, hasNatural: false,
                                                                     drew: true))
            let settled = BlackjackSpeechMap.plan(for: .handSettled(handIndex: 0, handCount: 1,
                                                                     outcome: .lose, total: 18,
                                                                     bet: 20, net: -20))
            let cause = BlackjackSpeechMap.text(for: dealer.synthesis!)
            let effect = BlackjackSpeechMap.text(for: settled.synthesis!)

            XCTAssertTrue(cause.contains("19"), "the player is told what beat them: \(cause)")
            XCTAssertTrue(effect.contains("20"), "…and what it cost: \(effect)")

            // Neither may be sacrificed when the channel is under pressure.
            XCTAssertEqual(BlackjackSpeechMap.priority(for: dealer.synthesis!), .high)
            XCTAssertEqual(BlackjackSpeechMap.priority(for: settled.synthesis!), .high)
        }
    }
}
