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

    /// The dealer's card waits for the hand's focus-landing read to FINISH, not
    /// for a fixed guess (D-097): the delay is the estimated length of that read,
    /// so it scales with the hand and never cuts it off.
    @MainActor
    func testTheDealerRevealWaitsForTheWholeHandToBeRead() {
        let short = BlackjackPacing.dealerRevealDelay(
            afterReading: "La tua mano: diciassette. Carte: asso, sei.")
        XCTAssertGreaterThan(short, 2.0,
                             "Long enough for the hand's total and cards to be read first.")

        // A longer hand line takes longer to clear — the wait tracks the content.
        let long = BlackjackPacing.dealerRevealDelay(
            afterReading: "Mano 1 di 2: venti. Carte: dieci di picche, dieci di cuori, asso.")
        XCTAssertGreaterThan(long, short, "The beat scales with the hand being read.")
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
        let window = runBet.lowerBound..<assign.lowerBound
        // A floor beat, then a wait for the channel to be quiet — both before the box.
        XCTAssertNotNil(model.range(of: "betBoxLeadIn", range: window),
                        "a floor beat so a just-settled round is in flight")
        XCTAssertNotNil(model.range(of: "await awaitSpokenChannelQuiet()", range: window),
                        "then the box waits for the spoken channel to fall quiet")
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
