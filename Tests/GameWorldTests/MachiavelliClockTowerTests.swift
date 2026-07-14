// MachiavelliClockTowerTests.swift
// =====================================================================
// The ClockTower's GameWorld economy (D-072/D-075): the Machiavelli table rules, the
// progressive-encounter store, and the REFUND — the second life of the scoring, where a
// loser recovers a share of the buy-in by how well they played, and the real chip
// movement with DEBUG_FREE_PLAY OFF (the test that actually matters).

import XCTest
@testable import GameWorld
@testable import GameEngine

final class MachiavelliClockTowerTests: XCTestCase {

    func testClockTowerRulesAreLowBuyIn() {
        let rules = MachiavelliTableRules.clockTower
        XCTAssertEqual(rules.buyIn, 1200)                       // just above the Riverwood
        XCTAssertLessThan(rules.buyIn, 5000)                    // far below the Skypool — most accessible
        XCTAssertEqual(rules.handSize, MachiavelliConstants.handSize)
    }

    func testProgressStoreCountsGamesPlayed() {
        let store = InMemoryMachiavelliProgress()
        XCTAssertEqual(store.loadGamesPlayed(), 0)
        store.saveGamesPlayed(3)
        XCTAssertEqual(store.loadGamesPlayed(), 3)
    }

    // MARK: - The refund curve (D-075)

    func testRefundCurveOverItsWholeRange() {
        let buyIn = 1200
        // Played well, lost narrowly → up to ~20% back.
        XCTAssertEqual(MachiavelliRefund.refundFraction(score: 90), 0.20, accuracy: 0.0001)
        XCTAssertEqual(MachiavelliRefund.refundFraction(score: 120), 0.20, accuracy: 0.0001)  // capped
        XCTAssertEqual(MachiavelliRefund.refund(score: 90, buyIn: buyIn), 240)
        // Middling loser → a partial refund between the floor and the ceiling.
        XCTAssertEqual(MachiavelliRefund.refundFraction(score: 55), 0.10, accuracy: 0.0001)
        XCTAssertEqual(MachiavelliRefund.refund(score: 55, buyIn: buyIn), 120)
        // Laid almost nothing / sat on a heavy hand → ZERO (the mechanic must punish this).
        XCTAssertEqual(MachiavelliRefund.refundFraction(score: 20), 0)
        XCTAssertEqual(MachiavelliRefund.refundFraction(score: 0), 0)
        XCTAssertEqual(MachiavelliRefund.refundFraction(score: -30), 0)
        XCTAssertEqual(MachiavelliRefund.refund(score: 5, buyIn: buyIn), 0)
    }

    func testRefundIsMonotonicInScore() {
        var previous = -1.0
        for score in stride(from: 0, through: 120, by: 5) {
            let f = MachiavelliRefund.refundFraction(score: score)
            XCTAssertGreaterThanOrEqual(f, previous, "refund never decreases as the score rises")
            previous = f
        }
    }

    func testCashOutWinnerKeepsFullBuyInLoserGetsRefund() {
        // The winner keeps the full buy-in (prestige, D-072); a loser gets the refund.
        XCTAssertEqual(MachiavelliRefund.cashOut(won: true, score: 0, buyIn: 1200), 1200)
        XCTAssertEqual(MachiavelliRefund.cashOut(won: false, score: 90, buyIn: 1200), 240)
        XCTAssertEqual(MachiavelliRefund.cashOut(won: false, score: 0, buyIn: 1200), 0)
    }

    // MARK: - REAL chip movement with DEBUG_FREE_PLAY OFF (the test that counts, D-075)

    func testRealChipMovementWhenTheHeroWins() {
        // free-play OFF: the economy is live. Sit (−buyIn), win → cash out the full buy-in.
        let account = PlayerAccount(store: InMemoryChipsStore(chips: 5000), freePlay: false)
        let buyIn = 1200
        XCTAssertTrue(account.buyIn(buyIn))
        XCTAssertEqual(account.chips, 3800)
        account.cashOut(MachiavelliRefund.cashOut(won: true, score: 40, buyIn: buyIn))
        XCTAssertEqual(account.chips, 5000, "a winner cashes out the full buy-in → net zero")
    }

    func testRealChipMovementWhenTheHeroLosesButPlayedWell() {
        let account = PlayerAccount(store: InMemoryChipsStore(chips: 5000), freePlay: false)
        let buyIn = 1200
        _ = account.buyIn(buyIn)                                    // chips = 3800
        account.cashOut(MachiavelliRefund.cashOut(won: false, score: 90, buyIn: buyIn))  // +240
        XCTAssertEqual(account.chips, 4040, "a strong loser recovers ~20% (240 of 1200)")
    }

    func testRealChipMovementWhenTheHeroLosesBadly() {
        let account = PlayerAccount(store: InMemoryChipsStore(chips: 5000), freePlay: false)
        let buyIn = 1200
        _ = account.buyIn(buyIn)                                    // chips = 3800
        account.cashOut(MachiavelliRefund.cashOut(won: false, score: 5, buyIn: buyIn))   // +0
        XCTAssertEqual(account.chips, 3800, "a player who laid almost nothing recovers zero")
    }

    // MARK: - Single-hand game

    func testTheGameIsASingleHand() async throws {
        let seats = (0..<2).map { pos in
            MachiavelliSeatAssignment(position: pos, playerID: pos,
                provider: MachiavelliBotTurnProvider(
                    HeuristicMachiavelliBot(personality: pos == 0 ? .machiavelliStudent : .machiavelliAdult,
                                            seed: UInt64(pos) * 131 &+ 5, budget: .nodes(700))))
        }
        let d = MachiavelliSessionDriver(capacity: 2, seats: seats, handSize: 4, seed: 9, turnLimit: 16)
        let outcome = try await d.playMatch()
        XCTAssertEqual(outcome.handsPlayed, 1)
        XCTAssertTrue((0..<2).contains(outcome.winnerID))
        await d.endSession()
    }
}
