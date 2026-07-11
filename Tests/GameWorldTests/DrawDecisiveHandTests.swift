import XCTest
@testable import GameWorld
import GameEngine

/// Progressive ante (D-052) and decisive hands (D-053) at the Whiskey draw table.
final class DrawDecisiveHandTests: XCTestCase {

    /// A shared, mode-switchable provider: when `opens` is false everyone checks
    /// (every deal passes in); when true the first actor opens and the rest call.
    private final class ModeProvider: DrawActionProvider {
        var opens: Bool
        init(opens: Bool) { self.opens = opens }
        func provideAction(for context: DrawBotContext) async -> DrawAction {
            if opens && context.legal.canBet { return .bet }
            if context.legal.canCall { return .call }
            return context.legal.canCheck ? .check : .fold
        }
        func provideDiscards(for context: DrawDrawContext) async -> [Card] { [] }
    }

    private func driver(_ provider: DrawActionProvider, chips: Int = 100_000, seed: UInt64 = 1,
                        progressiveAnte: Bool = false, decisiveHands: Bool = false) -> DrawSessionDriver {
        DrawSessionDriver(capacity: 4,
                          seats: (0..<4).map { DrawSeatAssignment(position: $0, playerID: $0, chips: chips, provider: provider) },
                          buttonPosition: 0, ante: 20, smallBet: 20, bigBet: 40, seed: seed,
                          progressiveAnte: progressiveAnte, decisiveHands: decisiveHands)
    }

    private func collect(_ d: DrawSessionDriver, _ body: @escaping () async throws -> Void) async throws -> [DrawEventPayload] {
        let stream = await d.events(as: .spectator)
        let task = Task { () -> [DrawEventPayload] in
            var out: [DrawEventPayload] = []
            for await e in stream { out.append(e.payload) }
            return out
        }
        try await body()
        await d.endSession()
        return await task.value
    }

    // MARK: - Progressive ante (D-052)

    func testAnteGrows20PercentPerPassAndOut() async throws {
        let d = driver(ModeProvider(opens: false), progressiveAnte: true)   // everyone checks → all pass
        let outcomes = try await d.run(maxHands: 5)
        // Base 20, then round(prev × 1.2) each pass: 20, 24, 29, 35, 42.
        XCTAssertEqual(outcomes.map { $0.ante }, [20, 24, 29, 35, 42])
        XCTAssertTrue(outcomes.allSatisfy { !$0.wasPlayed })
    }

    func testAnteReturnsToBaseAfterAPlayedHand() async throws {
        let provider = ModeProvider(opens: false)
        let d = driver(provider, progressiveAnte: true)
        _ = try await d.playHand()   // pass, ante 20 → next 24
        _ = try await d.playHand()   // pass, ante 24 → next 29
        XCTAssertEqual(d.currentAnte, 29)
        provider.opens = true
        let played = try await d.playHand()   // played with the grown ante
        XCTAssertTrue(played.wasPlayed)
        XCTAssertEqual(played.ante, 29, "the played hand uses the grown ante")
        XCTAssertEqual(d.currentAnte, 20, "after a played hand the ante returns to base")
    }

    // MARK: - Decisive hands (D-053)

    func testDecisiveIsForcedAfterThreeConsecutivePasses() async throws {
        let d = driver(ModeProvider(opens: false), progressiveAnte: true, decisiveHands: true)
        let outcomes = try await d.run(maxHands: 4)
        XCTAssertFalse(outcomes[0].wasDecisive)
        XCTAssertFalse(outcomes[1].wasDecisive)
        XCTAssertFalse(outcomes[2].wasDecisive)
        XCTAssertTrue(outcomes[3].wasDecisive, "the hand after three straight pass-and-outs is forced decisive")
    }

    func testDecisiveHandDoublesBetsAndLiftsTheRaiseCap() async throws {
        let d = driver(ModeProvider(opens: false), progressiveAnte: true, decisiveHands: true)
        let events = try await collect(d) { _ = try await d.run(maxHands: 4) }
        let decisive = events.compactMap { payload -> (Int, Int, Int)? in
            if case let .decisiveHandStarted(s, b, m) = payload { return (s, b, m) }
            return nil
        }
        XCTAssertEqual(decisive.count, 1, "exactly one decisive hand in the four dealt")
        XCTAssertEqual(decisive[0].0, 40, "small bet doubled (20→40)")
        XCTAssertEqual(decisive[0].1, 80, "big bet doubled (40→80)")
        XCTAssertEqual(decisive[0].2, 5, "raise cap lifted to 5")
    }

    func testDecisiveIntervalIsWithinFiveToEightPlayedHands() async throws {
        // Every deal is played (the opener opens, the rest call), so the counter
        // advances each hand; the first decisive must land at index 5…8 (D-053).
        for seed in UInt64(0)..<20 {
            let d = driver(ModeProvider(opens: true), chips: 1_000_000, seed: seed, decisiveHands: true)
            let outcomes = try await d.run(maxHands: 12)
            let first = outcomes.firstIndex { $0.wasDecisive }
            let index = try XCTUnwrap(first, "seed \(seed): no decisive hand within 12 played hands")
            XCTAssertTrue((5...8).contains(index), "seed \(seed): first decisive at index \(index), not in 5…8")
        }
    }

    func testNoDecisiveHandsWhenDisabled() async throws {
        let d = driver(ModeProvider(opens: true), chips: 1_000_000, decisiveHands: false)
        let outcomes = try await d.run(maxHands: 12)
        XCTAssertTrue(outcomes.allSatisfy { !$0.wasDecisive })
        XCTAssertTrue(outcomes.allSatisfy { $0.ante == 20 }, "no progressive ante or decisive boost when disabled")
    }
}
