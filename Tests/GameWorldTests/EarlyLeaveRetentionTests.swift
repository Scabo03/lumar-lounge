// EarlyLeaveRetentionTests.swift
// =====================================================================
// D-099 — what a poker player keeps when they stand up early.
//
// The formula is pure and casino-agnostic (a ratio of stacks), so these are
// unit tests on the fractions; the economic wiring (free play OFF) is proven
// in AbandonTableTests.

import XCTest
@testable import GameWorld

final class EarlyLeaveRetentionTests: XCTestCase {

    // MARK: - The anchors from the request

    func testDoublingEveryOpponentKeepsTheWholeStack() {
        // 3000 vs two opponents summing 1500 → lead 2.0 → 100%.
        XCTAssertEqual(EarlyLeaveRetention.retained(
            heroStack: 3000, aliveOpponentStacks: [900, 600], eliminatedCount: 0), 3000)
    }

    func testThirtyPercentAheadKeepsNinety() {
        // 1300 vs 1000 → lead 1.3 → 90%.
        XCTAssertEqual(EarlyLeaveRetention.retained(
            heroStack: 1300, aliveOpponentStacks: [1000], eliminatedCount: 0), 1170)
    }

    func testDeadEvenKeepsHalf() {
        XCTAssertEqual(EarlyLeaveRetention.retained(
            heroStack: 1000, aliveOpponentStacks: [1000], eliminatedCount: 0), 500)
    }

    func testWellBehindKeepsAQuarter() {
        // 400 vs 1000 → lead 0.4 → floor 25%.
        XCTAssertEqual(EarlyLeaveRetention.retained(
            heroStack: 400, aliveOpponentStacks: [1000], eliminatedCount: 0), 100)
    }

    // MARK: - Eliminating an opponent is a floor of half

    func testEliminatingAnOpponentGuaranteesAtLeastHalfEvenWhenBehind() {
        // Behind the one remaining opponent (lead 0.6 → ~30%), but one already busted →
        // floor 50%.
        let kept = EarlyLeaveRetention.retained(
            heroStack: 600, aliveOpponentStacks: [1000], eliminatedCount: 1)
        XCTAssertEqual(kept, 300, "half of the stack, from the elimination floor")
    }

    func testTheRatioStillLiftsAboveTheEliminationFloorWhenAhead() {
        // One busted (floor 50%) but also 30% ahead of the survivor (90%) → the higher wins.
        let kept = EarlyLeaveRetention.retained(
            heroStack: 1300, aliveOpponentStacks: [1000], eliminatedCount: 1)
        XCTAssertEqual(kept, 1170, "the ratio's 90% beats the 50% floor")
    }

    // MARK: - Monotonic and bounded

    func testKeepingMoreTheFurtherAheadYouAre() {
        var last = -1
        for hero in stride(from: 200, through: 3000, by: 100) {
            let kept = EarlyLeaveRetention.retained(
                heroStack: hero, aliveOpponentStacks: [1000], eliminatedCount: 0)
            XCTAssertGreaterThanOrEqual(kept, last, "retention must never decrease as the lead grows")
            XCTAssertLessThanOrEqual(kept, hero, "you can never keep more than your stack")
            last = kept
        }
    }

    func testNothingToKeepWithAnEmptyStack() {
        XCTAssertEqual(EarlyLeaveRetention.retained(
            heroStack: 0, aliveOpponentStacks: [1000], eliminatedCount: 1), 0)
    }

    func testTotalDominationWhenNoOpponentIsLeftIsWholeStack() {
        // Cannot happen at a real voluntary leave (busting all ends the session), but the
        // function is total: no live opponents → keep everything.
        XCTAssertEqual(EarlyLeaveRetention.retained(
            heroStack: 2000, aliveOpponentStacks: [], eliminatedCount: 2), 2000)
    }

    // MARK: - Casino-agnostic

    func testTheSameLEADKeepsTheSameFractionAtAnyStakes() {
        // Riverwood-sized and Skypool-sized stacks with the SAME 1.3 lead keep the same 90%.
        XCTAssertEqual(EarlyLeaveRetention.retained(
            heroStack: 1300, aliveOpponentStacks: [1000], eliminatedCount: 0), 1170)
        XCTAssertEqual(EarlyLeaveRetention.retained(
            heroStack: 13000, aliveOpponentStacks: [10000], eliminatedCount: 0), 11700)
    }
}
