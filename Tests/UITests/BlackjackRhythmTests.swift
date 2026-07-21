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

        // The lead must cover the device's read-start latency, not just the read (D-100):
        // even the short total-only line clears with margin.
        XCTAssertGreaterThan(BlackjackPacing.dealerRevealDelay(afterReading: "La tua mano: 17."), 2.5,
                             "the dealer must not fire while the total is still being read")
    }

    /// The wait before the next wager box was raised (D-100): the end-of-hand line
    /// needs room to be understood before the pop-up arrives.
    func testTheWagerBoxLeadInLeavesRoomToUnderstandTheRound() {
        XCTAssertGreaterThanOrEqual(BlackjackPacing.betBoxLeadIn, 3.0,
                                    "a couple of seconds more than before, so the round lands")
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
        XCTAssertTrue(view.contains(".accessibilitySortPriority(90 - Double(index) * 2)"), "hand TOTAL next")
        XCTAssertTrue(view.contains(".accessibilitySortPriority(50 - Double(index) * 2)"),
                      "the cards sit AFTER the moves (below 66)")
        XCTAssertTrue(view.contains(".accessibilitySortPriority(40)"), "then the stakes line")
        XCTAssertTrue(view.contains(".accessibilitySortPriority(5)"), "leaving the table comes last")

        // THE FIRM RULE (D-100): from the total, a swipe goes straight to the moves —
        // every move sits between the total (90) and the cards (50).
        XCTAssertTrue(bar.contains(".accessibilitySortPriority(sortPriority)"),
                      "the moves declare their place rather than inheriting it")
        for (move, priority) in [("action.hit", 70), ("action.stand", 69), ("action.double", 68),
                                 ("action.split", 67), ("action.surrender", 66)] {
            XCTAssertTrue(bar.contains("identifier: \"\(move)\", sortPriority: \(priority)"),
                          "\(move) must sit between the total and the cards")
            XCTAssertLessThan(priority, 90, "the moves come right after the total…")
            XCTAssertGreaterThan(priority, 50, "…and before the cards and the fiches line")
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

    /// The end-of-hand account is ONE line: the dealer cause and the result, built
    /// together so nothing can split them (D-098). Both parts are present, and the
    /// settlement it is delivered on is high, so it is never dropped.
    func testTheEndOfARoundExplainsBothTheCauseAndTheResultInOneLine() {
        italian {
            let cause = BlackjackSpeechMap.dealerClauseText(
                revealed: true, total: 19, isSoft: false, busted: false, natural: false)
            let result = BlackjackSpeechMap.text(for: .settled(
                index: 0, handCount: 1, outcome: .lose, amount: 20))
            let line = [cause, result].compactMap { $0 }.joined(separator: " ")

            XCTAssertTrue(line.contains("19"), "the player is told what beat them: \(line)")
            XCTAssertTrue(line.contains("20"), "…and what it cost, in the same breath: \(line)")

            // The settlement it rides on is never sacrificed under channel pressure.
            XCTAssertEqual(BlackjackSpeechMap.priority(for: .settled(
                index: 0, handCount: 1, outcome: .lose, amount: 20)), .high)
        }
    }

    /// The AUTOMATIC read on the deal is the TOTAL alone — short, so it is never
    /// cut off — with the cards on a sibling element for a player who studies the
    /// hand (D-098). Total and cards are disjoint: neither repeats the other.
    @MainActor
    func testTheHandSplitsIntoTotalAndCardsSoTheAutoReadIsShort() {
        italian {
            let hand = BlackjackHandPresentation(cards: [Card(.ace, .spades), Card(.six, .hearts)],
                                                 bet: 20)
            let total = BlackjackReadout.total(hand, index: 0, handCount: 1)
            let cards = BlackjackReadout.handCards(hand)

            XCTAssertTrue(total.contains("17"), "the total element carries the amount: \(total)")
            XCTAssertFalse(total.lowercased().contains("asso"),
                           "the total element does NOT read the cards: \(total)")
            XCTAssertTrue(cards.lowercased().contains("asso"),
                          "the cards live on their own element: \(cards)")
            // Short enough that the dealer reveal, which waits on it, follows promptly.
            XCTAssertLessThan(AnnouncementQueue.speakTime(total),
                              AnnouncementQueue.speakTime(BlackjackReadout.hand(hand, index: 0, handCount: 1)),
                              "the total-only read is shorter than total+cards")
        }
    }
}
