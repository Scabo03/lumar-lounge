import XCTest
@testable import GameWorld
import GameEngine

/// Verifies the production seed fix (D-047): with NO injected seed, each session's
/// driver deals fresh RANDOM cards every hand; with an injected seed it stays fully
/// deterministic (so tests remain reproducible). These particular tests use REAL
/// system randomness on purpose — the thresholds are loose enough never to fail by
/// chance yet tight enough to catch the bug (which made every session identical).
final class SeedRandomizationTests: XCTestCase {

    // Passive providers just check/call (Texas) or open-then-stand-pat (Draw), enough
    // to deal cards and reach showdowns without steering the randomness.
    private struct PassiveTexas: ActionProvider {
        func provideAction(for context: BotContext) async -> Action {
            if context.legal.canCheck { return .check }
            if context.legal.canCall { return .call }
            return .fold
        }
    }
    private struct OpenerDraw: DrawActionProvider {
        func provideAction(for context: DrawBotContext) async -> DrawAction {
            if context.legal.canBet { return .bet }
            if context.legal.canCall { return .call }
            return context.legal.canCheck ? .check : .fold
        }
        func provideDiscards(for context: DrawDrawContext) async -> [Card] { [] }
    }

    // MARK: - Event collection helpers

    private func texasPayloads(seed: UInt64?, hands: Int) async throws -> [EventPayload] {
        let driver = SessionDriver(
            capacity: 4,
            seats: (0..<4).map { SeatAssignment(position: $0, playerID: $0, chips: 1000, provider: PassiveTexas()) },
            buttonPosition: 0, smallBlind: 5, bigBlind: 10, seed: seed)
        let stream = await driver.events(as: .player(0))
        let collector = Task { () -> [EventPayload] in
            var out: [EventPayload] = []
            for await e in stream { out.append(e.payload) }
            return out
        }
        _ = try await driver.run(maxHands: hands)
        await driver.endSession()
        return await collector.value
    }

    private func drawPayloads(seed: UInt64?, deals: Int) async throws -> [DrawEventPayload] {
        let driver = DrawSessionDriver(
            capacity: 4,
            seats: (0..<4).map { DrawSeatAssignment(position: $0, playerID: $0, chips: 2000, provider: OpenerDraw()) },
            buttonPosition: 0, ante: 10, smallBet: 20, bigBet: 40, seed: seed)
        let stream = await driver.events(as: .player(0))
        let collector = Task { () -> [DrawEventPayload] in
            var out: [DrawEventPayload] = []
            for await e in stream { out.append(e.payload) }
            return out
        }
        _ = try await driver.run(maxHands: deals)
        await driver.endSession()
        return await collector.value
    }

    private func texasHoleCards(_ payloads: [EventPayload]) -> [[Card]] {
        payloads.compactMap { if case let .privateHoleCards(s, cs) = $0, s == 0 { return cs } else { return nil } }
    }
    private func drawHoleCards(_ payloads: [DrawEventPayload]) -> [[Card]] {
        payloads.compactMap { if case let .privateCards(s, cs) = $0, s == 0 { return cs } else { return nil } }
    }
    private func key(_ cards: [Card]) -> String { cards.map(\.description).joined(separator: ",") }

    // MARK: - Production: successive sessions differ

    func testProductionTexasSessionsDealDifferentFirstCards() async throws {
        var firsts: [String] = []
        for _ in 0..<10 {
            let hole = texasHoleCards(try await texasPayloads(seed: nil, hands: 1))
            firsts.append(key(hole.first ?? []))
        }
        // The bug made all ten identical; a real random source makes ≥9 distinct.
        XCTAssertGreaterThanOrEqual(Set(firsts).count, 9, "production Texas sessions should deal different cards")
    }

    func testProductionDrawSessionsDealDifferentFirstCards() async throws {
        var firsts: [String] = []
        for _ in 0..<10 {
            let hole = drawHoleCards(try await drawPayloads(seed: nil, deals: 1))
            firsts.append(key(hole.first ?? []))
        }
        XCTAssertGreaterThanOrEqual(Set(firsts).count, 9, "production Draw sessions should deal different cards")
    }

    // MARK: - Production: variety within one long session

    func testProductionTexasSessionHasVariedHandsAndWinners() async throws {
        let payloads = try await texasPayloads(seed: nil, hands: 20)
        let hole = texasHoleCards(payloads)
        XCTAssertGreaterThanOrEqual(hole.count, 15, "should have played enough hands to judge variety")
        // The human's private cards vary hand to hand (allow a rare natural collision).
        XCTAssertGreaterThanOrEqual(Set(hole.map(key)).count, hole.count - 2,
                                    "the human's cards should differ almost every hand")
        // Winners are not a single fixed seat.
        let winners = payloads.flatMap { payload -> [Int] in
            if case let .potAwarded(_, _, w) = payload { return w } else { return [] }
        }
        XCTAssertGreaterThanOrEqual(Set(winners).count, 2, "winners should be distributed, not always the same seat")
    }

    func testProductionDrawSessionHasVariedHands() async throws {
        let payloads = try await drawPayloads(seed: nil, deals: 20)
        let hole = drawHoleCards(payloads)
        XCTAssertGreaterThanOrEqual(hole.count, 15, "should have dealt enough hands to judge variety")
        XCTAssertGreaterThanOrEqual(Set(hole.map(key)).count, hole.count - 2,
                                    "the human's five cards should differ almost every deal")
    }

    // MARK: - Injected seed stays deterministic (tests remain reproducible)

    func testInjectedSeedIsFullyDeterministicTexas() async throws {
        let a = texasHoleCards(try await texasPayloads(seed: 4242, hands: 5)).map(key)
        let b = texasHoleCards(try await texasPayloads(seed: 4242, hands: 5)).map(key)
        XCTAssertEqual(a, b, "a fixed seed must reproduce the exact same deals")
        XCTAssertFalse(a.isEmpty)
    }

    func testInjectedSeedIsFullyDeterministicDraw() async throws {
        let a = drawHoleCards(try await drawPayloads(seed: 4242, deals: 5)).map(key)
        let b = drawHoleCards(try await drawPayloads(seed: 4242, deals: 5)).map(key)
        XCTAssertEqual(a, b, "a fixed seed must reproduce the exact same deals")
        XCTAssertFalse(a.isEmpty)
    }
}
