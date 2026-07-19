// BlackjackTableTests.swift
// =====================================================================
// The reducer, the wager box, and the two guardians that matter most:
// the system never advises the move, and the three casinos that already
// existed are untouched.

import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine

final class BlackjackTableTests: XCTestCase {

    private func card(_ rank: Rank, _ suit: Suit = .spades) -> Card { Card(rank, suit) }

    // MARK: - The reducer

    func testTheDealPutsBothHandsOnTheTableWithTheHoleCardStillDown() {
        var state = BlackjackTableState()
        state = BlackjackTableReducer.reduce(state, .sessionBegan(chips: 1000,
                                                                  minimumBet: 20, maximumBet: 200))
        state = BlackjackTableReducer.reduce(state, .roundBegan(roundNumber: 1, bet: 20, chips: 980))
        state = BlackjackTableReducer.reduce(state, .dealt(playerCards: [card(.ace), card(.six, .hearts)],
                                                            total: 17, isSoft: true,
                                                            dealerUpCard: card(.ten, .clubs),
                                                            isNatural: false))

        XCTAssertEqual(state.chips, 980, "The wager has left the player's fiches.")
        XCTAssertEqual(state.hands.count, 1)
        XCTAssertEqual(state.hands[0].total, 17)
        XCTAssertTrue(state.hands[0].isSoft)
        XCTAssertEqual(state.dealerCards.count, 1, "Only the up card is known.")
        XCTAssertTrue(state.holeCardHidden)
    }

    func testASplitRebuildsTheTableFromTheEventItself() {
        var state = BlackjackTableState(chips: 980, bet: 20)
        state = BlackjackTableReducer.reduce(state, .dealt(playerCards: [card(.eight), card(.eight, .hearts)],
                                                            total: 16, isSoft: false,
                                                            dealerUpCard: card(.nine), isNatural: false))
        state = BlackjackTableReducer.reduce(state,
            .playerActed(handIndex: 0,
                         action: .split(hands: [[card(.eight), card(.three)],
                                                [card(.eight, .hearts), card(.two)]], wager: 20),
                         chips: 960))

        XCTAssertEqual(state.hands.count, 2)
        XCTAssertEqual(state.hands[0].total, 11)
        XCTAssertEqual(state.hands[1].total, 10)
        XCTAssertEqual(state.totalAtStake, 40, "Two hands, two wagers.")
        XCTAssertEqual(state.chips, 960, "The second wager has left the fiches.")
        XCTAssertTrue(state.hasSplit)
    }

    func testChipsStayCurrentThroughADoubleSoLeavingCannotOverpay() {
        // D-086 forfeits whatever is on the felt by cashing out what is LEFT,
        // which is only right if the left-over figure is never stale.
        var state = BlackjackTableState(chips: 980, bet: 20)
        state = BlackjackTableReducer.reduce(state, .dealt(playerCards: [card(.five), card(.six)],
                                                            total: 11, isSoft: false,
                                                            dealerUpCard: card(.nine), isNatural: false))
        state = BlackjackTableReducer.reduce(state,
            .playerActed(handIndex: 0,
                         action: .doubled(card: card(.ten), total: 21, wager: 40, didBust: false),
                         chips: 960))

        XCTAssertEqual(state.chips, 960)
        XCTAssertEqual(state.totalAtStake, 40)
    }

    func testTheDealerRevealAndTheSettlementLandOnTheState() {
        var state = BlackjackTableState(chips: 980, bet: 20)
        state = BlackjackTableReducer.reduce(state, .dealt(playerCards: [card(.ten), card(.nine)],
                                                            total: 19, isSoft: false,
                                                            dealerUpCard: card(.six), isNatural: false))
        state = BlackjackTableReducer.reduce(state, .dealerPlayed(cards: [card(.six), card(.ten, .hearts),
                                                                          card(.eight)],
                                                                   total: 24, isSoft: false,
                                                                   didBust: true, hasNatural: false,
                                                                   drew: true))
        XCTAssertFalse(state.holeCardHidden)
        XCTAssertTrue(state.dealerBusted)

        state = BlackjackTableReducer.reduce(state, .handSettled(handIndex: 0, handCount: 1,
                                                                  outcome: .win, total: 19,
                                                                  bet: 20, net: 20))
        state = BlackjackTableReducer.reduce(state, .roundEnded(roundNumber: 1, net: 20,
                                                                 chips: 1020, handCount: 1))
        XCTAssertEqual(state.hands[0].outcome, .win)
        XCTAssertEqual(state.chips, 1020)
        XCTAssertEqual(state.lastRoundNet, 20)
    }

    // MARK: - The wager box

    func testTheWagerBoxMovesInWholeTableMinimumsAndStaysInTheBand() {
        var box = BlackjackBetBox(minimum: 20, maximum: 200)
        XCTAssertEqual(box.value, 20)
        XCTAssertTrue(box.isAtMin)

        box.increase()
        XCTAssertEqual(box.value, 40)
        box.decrease()
        XCTAssertEqual(box.value, 20)
        box.decrease()
        XCTAssertEqual(box.value, 20, "It cannot go under the table minimum.")

        box.toMax()
        XCTAssertEqual(box.value, 200)
        XCTAssertTrue(box.isAtMax)
        box.increase()
        XCTAssertEqual(box.value, 200, "It cannot go over the table maximum.")
    }

    func testTheWagerBoxNeverOffersMoreThanThePlayerHolds() {
        // Ninety fiches at a twenty table: the most that can be staked is eighty.
        let box = BlackjackBetBox(minimum: 20, maximum: 90)
        XCTAssertEqual(box.ceiling, 80)

        var maxed = box
        maxed.toMax()
        XCTAssertEqual(maxed.value, 80)
        XCTAssertEqual(maxed.value % 20, 0, "Every offered wager is a whole multiple.")
    }

    func testEveryOfferedWagerKeepsThePayoutsExact() {
        // The reason wagers snap to even multiples: three-to-two and half-back
        // must never lose a chip to integer division.
        for minimum in [20, 100] {
            var box = BlackjackBetBox(minimum: minimum, maximum: minimum * 10)
            for _ in 0 ..< 10 {
                XCTAssertEqual(box.value % 2, 0, "\(box.value) must be even.")
                XCTAssertEqual(box.value * 3 / 2 * 2, box.value * 3,
                               "Three-to-two on \(box.value) must be exact.")
                XCTAssertEqual((box.value / 2) * 2, box.value,
                               "Half of \(box.value) must be exact.")
                box.increase()
            }
        }
    }

    // MARK: - The guardian: DESCRIBE, never ADVISE (D-091)

    func testNoBlackjackStringEverSuggestsAMove() throws {
        // Blackjack has a famous optimal strategy and it would be trivial to
        // whisper it. The sighted player gets no hint, so neither does anyone
        // else — this scans the shipped Italian strings for advisory language.
        let strings = try italianStrings()
        let blackjackKeys = strings.filter { $0.key.hasPrefix("blackjack.") }
        XCTAssertGreaterThan(blackjackKeys.count, 30, "The scan must actually have strings to scan.")

        // Second-person advice, recommendation, and the vocabulary of strategy.
        let forbidden = ["conviene", "dovresti", "ti consiglio", "consigliat",
                         "meglio ", "ottimale", "strategia", "suggerit",
                         "prova a", "ti suggerisco", "faresti bene"]

        for (key, value) in blackjackKeys {
            let lower = value.lowercased()
            for phrase in forbidden {
                XCTAssertFalse(lower.contains(phrase),
                               "\(key) advises the player: \"\(value)\" contains \"\(phrase)\"")
            }
        }
    }

    func testTheSpokenLinesDescribeStateAndNothingMore() {
        // A sweep over the real rendered lines, not just the raw strings.
        let lines: [BlackjackSynthLine] = [
            .deal(total: 16, isSoft: false, dealerUpCard: Card(.ten, .clubs), isNatural: false),
            .deal(total: 21, isSoft: false, dealerUpCard: Card(.ace, .spades), isNatural: true),
            .drew(card: Card(.five, .hearts), total: 21, isSoft: false, didBust: false),
            .drew(card: Card(.ten, .hearts), total: 26, isSoft: false, didBust: true),
            .doubled(card: Card(.ten, .hearts), total: 21, isSoft: false, didBust: false),
            .split(handCount: 2),
            .dealer(cards: [Card(.ten, .clubs), Card(.seven, .hearts)], total: 17,
                    isSoft: false, didBust: false, hasNatural: false),
            .settled(index: 0, handCount: 1, outcome: .natural, amount: 30),
            .settled(index: 0, handCount: 2, outcome: .surrender, amount: 10),
            .roundNet(net: -40)
        ]
        let forbidden = ["conviene", "dovresti", "consigli", "ottimale", "strategia"]
        for line in lines {
            let text = BlackjackSpeechMap.text(for: line).lowercased()
            XCTAssertFalse(text.isEmpty)
            for phrase in forbidden {
                XCTAssertFalse(text.contains(phrase), "\(line) advises: \(text)")
            }
        }
    }

    func testTheSoftnessOfATotalIsDescribedBecauseItChangesWhatTheHandCanDo() {
        // The one adjective the player is given. It is a FACT about the cards
        // (an ace counting eleven), not a hint about what to do with them.
        XCTAssertNotEqual(BlackjackSpeechMap.totalPhrase(17, true),
                          BlackjackSpeechMap.totalPhrase(17, false))
    }

    // MARK: - Priorities

    func testNothingSpokenAtABlackjackTableIsDroppableChatter() {
        // The player is alone against the house: every line is personal, and
        // the ones carrying money are never droppable.
        let money: [BlackjackSynthLine] = [
            .deal(total: 16, isSoft: false, dealerUpCard: Card(.ten, .clubs), isNatural: false),
            .settled(index: 0, handCount: 1, outcome: .win, amount: 20),
            .roundNet(net: 20)
        ]
        for line in money {
            XCTAssertEqual(BlackjackSpeechMap.priority(for: line), .high)
        }
    }

    // MARK: - The other casinos are untouched

    func testTheThreeExistingCasinosStillHoldExactlyTheTablesTheyDid() {
        // Blackjack lands at the Riverwood and the Skypool. The ClockTower is a
        // special place with two games and does NOT receive it.
        XCTAssertEqual(Casinos.clockTower.tables.count, 2)
        XCTAssertFalse(Casinos.clockTower.tables.contains {
            if case .blackjack = $0.game { return true }
            return false
        }, "The ClockTower must not host blackjack.")

        // The pre-existing tables are all still there, unchanged, in order.
        XCTAssertEqual(Array(Casinos.riverwood.tables.prefix(3)).map(\.id),
                       ["riverwood.table.classic", "riverwood.table.fast", "riverwood.table.draw"])
        XCTAssertEqual(Array(Casinos.skypool.tables.prefix(3)).map(\.id),
                       ["skypool.table.fast", "skypool.table.classic", "skypool.table.marble"])
        XCTAssertEqual(Casinos.clockTower.tables.map(\.id),
                       ["clocktower.table.machiavelli", "clocktower.table.stud"])

        // And their buy-ins have not moved.
        XCTAssertEqual(Casinos.riverwood.tables[0].buyIn, 1000)
        XCTAssertEqual(Casinos.riverwood.tables[2].buyIn, 2000)
        XCTAssertEqual(Casinos.skypool.tables[2].buyIn, 10_000)
        XCTAssertEqual(Casinos.clockTower.tables[1].buyIn, 3000)
    }

    func testBlackjackSitsAtBothHousesInTheirOwnEconomies() throws {
        let riverwood = try XCTUnwrap(Casinos.riverwood.tables.last)
        let skypool = try XCTUnwrap(Casinos.skypool.tables.last)
        XCTAssertEqual(riverwood.id, "riverwood.table.blackjack")
        XCTAssertEqual(skypool.id, "skypool.table.blackjack")
        XCTAssertEqual(riverwood.buyIn, 1000)
        XCTAssertEqual(skypool.buyIn, 5000)

        // The palette resolves by data — no audio-path change was needed (D-067).
        XCTAssertEqual(CasinoAudio.hosting(table: "riverwood.table.blackjack").id, "riverwood")
        XCTAssertEqual(CasinoAudio.hosting(table: "skypool.table.blackjack").id, "skypool")
    }

    // MARK: - Helper

    /// Reads the shipped Italian strings from disk. The `.strings` bundle is not
    /// loadable under `swift test`, so the file is parsed directly — the same
    /// approach `PhoneticsTests` uses.
    private func italianStrings() throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let url = root.appendingPathComponent("Resources/it.lproj/Localizable.strings")
        let contents = try String(contentsOf: url, encoding: .utf8)

        var result: [String: String] = [:]
        let pattern = #""([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(contents.startIndex..., in: contents)
        for match in regex.matches(in: contents, range: range) {
            guard let k = Range(match.range(at: 1), in: contents),
                  let v = Range(match.range(at: 2), in: contents) else { continue }
            result[String(contents[k])] = String(contents[v])
        }
        return result
    }
}
