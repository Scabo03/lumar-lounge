// MachiavelliClockTowerTests.swift
// =====================================================================
// The ClockTower's GameWorld additions (D-072): the Machiavelli table rules, the
// progressive-encounter store, and the driver refactor that emits `matchEnded` from
// `playHand` (so a UI can drive hands one-by-one, gated for pacing, and still see the
// match conclude).

import XCTest
@testable import GameWorld
@testable import GameEngine

final class MachiavelliClockTowerTests: XCTestCase {

    func testClockTowerRulesAreLowBuyIn() {
        let rules = MachiavelliTableRules.clockTower
        XCTAssertEqual(rules.buyIn, 1200)                       // just above the Riverwood, refundable
        XCTAssertLessThan(rules.buyIn, 5000)                    // far below the Skypool — most accessible
        XCTAssertEqual(rules.handSize, MachiavelliConstants.handSize)
    }

    func testProgressStoreCountsGamesPlayed() {
        let store = InMemoryMachiavelliProgress()
        XCTAssertEqual(store.loadGamesPlayed(), 0)
        store.saveGamesPlayed(3)
        XCTAssertEqual(store.loadGamesPlayed(), 3)
    }

    /// A driver of `count` bot players, small/fast for tests.
    private func driver(seed: UInt64?, threshold: Int) -> MachiavelliSessionDriver {
        let seats = (0..<2).map { pos in
            MachiavelliSeatAssignment(position: pos, playerID: pos,
                provider: MachiavelliBotTurnProvider(
                    HeuristicMachiavelliBot(personality: pos == 0 ? .machiavelliStudent : .machiavelliAdult,
                                            seed: UInt64(pos) * 131 &+ 5, budget: .nodes(700))))
        }
        return MachiavelliSessionDriver(capacity: 2, seats: seats, handSize: 4,
                                        victoryThreshold: threshold, seed: seed, turnLimit: 16, handLimit: 30)
    }

    func testPlayHandEmitsMatchEndedWhenThresholdCrossed() async throws {
        // Drive hands one at a time (as the UI does) and confirm `matchEnded` arrives
        // through the stream — without calling playMatch.
        let d = driver(seed: 9, threshold: 30)
        let stream = await d.events(as: .spectator)
        async let sawMatchEnd: Bool = {
            for await event in stream { if case .matchEnded = event.payload { return true } }
            return false
        }()
        while d.canDealNextHand { _ = try await d.playHand() }
        await d.endSession()
        let saw = await sawMatchEnd
        XCTAssertTrue(saw, "playHand emits matchEnded once a player crosses the threshold")
        XCTAssertTrue(d.isMatchOver)
    }

    func testPlayMatchStillWorks() async throws {
        let d = driver(seed: 9, threshold: 30)
        let outcome = try await d.playMatch()
        XCTAssertTrue((0..<2).contains(outcome.winnerID))
        XCTAssertGreaterThanOrEqual(outcome.handsPlayed, 1)
        await d.endSession()
    }
}
