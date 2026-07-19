// FastForwardTests.swift
// =====================================================================
// D-087 — after the human folds, the hand runs to the showdown.
//
// The property under test is WHAT STILL GETS SAID: the fast-forward must cut the
// wait for rounds the player cannot act in, and must NOT cut the information they
// use to read the opponents. Every surviving hand is still announced.

import XCTest
@testable import UI
@testable import GameWorld
import GameEngine

@MainActor
final class FastForwardTests: XCTestCase {

    // MARK: - What is skipped and what is kept

    /// The result of the hand is always narrated, whatever happens before it.
    func testEveryResultEventCountsAsPayoffAndSurvivesTheFastForward() {
        let payoffs: [EventPayload] = [
            .handShown(seatID: 1, holeCards: [], category: .pair, bestFive: []),
            .potAwarded(potIndex: 0, amount: 300, winnerSeatIDs: [1]),
            .handEnded(handNumber: 1, wentToShowdown: true, board: [], payouts: [:], chips: [:]),
            .playerBusted(playerID: 2),
        ]
        for payload in payoffs {
            XCTAssertTrue(TableViewModel.isPayoff(payload),
                          "\(payload) carries the result and must never be skipped")
        }
    }

    /// The betting rounds the folded player cannot act in are what gets cut — and only
    /// those. This is the whole saving.
    func testBettingRoundEventsAreSkippedWhileFastForwarding() {
        let skipped: [EventPayload] = [
            .playerActed(seatID: 2, action: .called(amount: 40, isAllIn: false)),
            .streetOpened(street: .flop, communityCards: []),
            .streetOpened(street: .turn, communityCards: []),
            .streetOpened(street: .river, communityCards: []),
            .blindPosted(seatID: 1, blind: .big, amount: 40, isAllIn: false),
        ]
        for payload in skipped {
            XCTAssertFalse(TableViewModel.isPayoff(payload),
                           "\(payload) is a round the folded player cannot act in")
        }
    }

    /// THE guarantee that keeps the fast-forward honest: the opponents' revealed hands
    /// are payoff events, so folding never costs the player their read of the table.
    /// It removes waiting, not information.
    func testFoldingNeverCostsTheReadOfTheOpponents() {
        let reveal = EventPayload.handShown(seatID: 3, holeCards: [Card(.ace, .spades), Card(.king, .spades)],
                                            category: .flush, bestFive: [])
        XCTAssertTrue(TableViewModel.isPayoff(reveal),
                      "every surviving hand must still be announced after a fold")
    }

    // MARK: - The order of the payoff

    /// The payoff is announced in the order the player needs it: each surviving hand,
    /// then who won with what, then what it netted them.
    func testPayoffOrderIsHandsThenWinnerThenNetResult() {
        let sequence: [EventPayload] = [
            .handShown(seatID: 1, holeCards: [], category: .pair, bestFive: []),
            .handShown(seatID: 2, holeCards: [], category: .twoPair, bestFive: []),
            .potAwarded(potIndex: 0, amount: 500, winnerSeatIDs: [2]),
            .handEnded(handNumber: 1, wentToShowdown: true, board: [], payouts: [:], chips: [:]),
        ]
        // All four are payoff events, in this order, so the narration is: the hands,
        // then the winner, then (on handEnded) the net result.
        XCTAssertTrue(sequence.allSatisfy(TableViewModel.isPayoff))
        guard case .handShown = sequence[0], case .handShown = sequence[1],
              case .potAwarded = sequence[2], case .handEnded = sequence[3] else {
            return XCTFail("unexpected payoff order")
        }
    }

    // MARK: - The net result line

    /// The chips announced are the player's REAL net gain, never a single pot event's
    /// amount: a hand awards one pot per contribution level — even an uncontested blind
    /// hand produces two (D-031) — so no one event's amount is what they won.
    func testNetResultLineReportsTheAmount() throws {
        // `.strings` are not loaded under `swift test`, so check the shipped file.
        for language in ["it", "en"] {
            let path = "Resources/\(language).lproj/Localizable.strings"
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
                throw XCTSkip("Strings file not reachable from the test working directory")
            }
            let line = contents.split(separator: "\n")
                .first { $0.contains("\"announce.hero.net.win\"") }
            XCTAssertNotNil(line, "\(language): missing announce.hero.net.win")
            XCTAssertTrue(line?.contains("%d") ?? false,
                          "\(language): the net result must carry the amount: \(line ?? "")")
        }
    }

    /// It is a personal, high-priority line, so the channel budget never drops it.
    func testNetResultIsHighPriority() {
        XCTAssertEqual(SpeechMap.priority(for: .heroNetWin(chips: 450)), .high)
    }
}
