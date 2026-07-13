import XCTest
@testable import GameWorld
@testable import GameEngine

/// The Omaha session driver (D-064): determinism, chip conservation, dead-button
/// rotation, private-card routing, and the hands-count stake escalation.
final class OmahaSessionDriverTests: XCTestCase {

    /// A three-bot driver (deterministic bots, low samples for speed).
    private func driver(seed: UInt64?, escalation: StakeEscalation = .none,
                        stacks: [Int] = [1000, 1000, 1000]) -> OmahaSessionDriver {
        let seats = stacks.enumerated().map { (pos, chips) in
            OmahaSeatAssignment(position: pos, playerID: pos, chips: chips,
                                provider: OmahaBotActionProvider(
                                    HeuristicOmahaBot(personality: [.eagerNovice, .conservativeRock, .hotAggressor][pos],
                                                      seed: UInt64(pos) * 101 &+ 7, equitySamples: 20)))
        }
        return OmahaSessionDriver(capacity: stacks.count, seats: seats, buttonPosition: 0,
                                  smallBlind: 5, bigBlind: 10, seed: seed, escalation: escalation)
    }

    func testChipsConservedAcrossASession() async throws {
        let d = driver(seed: 42)
        for _ in 0..<12 where d.canDealNextHand {
            let outcome = try await d.playHand()
            let total = outcome.chipsByPlayer.values.reduce(0, +)
            XCTAssertEqual(total, 3000, "chips are conserved across the whole session")
        }
        await d.endSession()
    }

    func testDeterministicGivenSeed() async throws {
        func run(_ seed: UInt64) async throws -> [[Int: Int]] {
            let d = driver(seed: seed)
            var chips: [[Int: Int]] = []
            for _ in 0..<8 where d.canDealNextHand { chips.append(try await d.playHand().chipsByPlayer) }
            await d.endSession()
            return chips
        }
        let a = try await run(2026)
        let b = try await run(2026)
        XCTAssertEqual(a, b, "same seed → identical session")
        let c = try await run(2027)
        XCTAssertNotEqual(a, c, "a different seed plays out differently")
    }

    func testProductionSeedIsRandomPerSession() async throws {
        // seed nil (production) → different cards each session (D-047). Two fresh
        // sessions should almost never produce the identical first-hand chip result.
        func firstHandChips() async throws -> [Int: Int] {
            let d = driver(seed: nil)
            let outcome = try await d.playHand()
            await d.endSession()
            return outcome.chipsByPlayer
        }
        var distinct = Set<String>()
        for _ in 0..<6 { distinct.insert("\(try await firstHandChips().sorted { $0.key < $1.key })") }
        XCTAssertGreaterThan(distinct.count, 1, "production (nil seed) deals different cards each session")
    }

    // MARK: - Stake escalation: keyed on HANDS PLAYED, never on time (D-064)

    func testBlindsEscalateOnHandsCountNotTime() async throws {
        // Every 3 played hands, blinds double.
        let d = driver(seed: 99, escalation: StakeEscalation(interval: 3, factor: 2))
        var byHand: [Int: (Int, Int, Int)] = [:]   // handNumber → (sb, bb, level)
        for _ in 0..<9 where d.canDealNextHand {
            let o = try await d.playHand()
            byHand[o.handNumber] = (o.smallBlind, o.bigBlind, o.escalationLevel)
        }
        await d.endSession()
        // The trigger is purely the count of played hands: hand 0..2 → level 0 (5/10),
        // 3..5 → level 1 (10/20), 6..8 → level 2 (20/40). No clock involved.
        XCTAssertEqual(byHand[0]!.0, 5);  XCTAssertEqual(byHand[0]!.1, 10); XCTAssertEqual(byHand[0]!.2, 0)
        XCTAssertEqual(byHand[3]!.0, 10); XCTAssertEqual(byHand[3]!.1, 20); XCTAssertEqual(byHand[3]!.2, 1)
        if let h6 = byHand[6] { XCTAssertEqual(h6.2, 2); XCTAssertEqual(h6.1, 40) }
    }

    func testNoEscalationByDefault() async throws {
        let d = driver(seed: 5)   // escalation .none
        for _ in 0..<6 where d.canDealNextHand {
            let o = try await d.playHand()
            XCTAssertEqual(o.smallBlind, 5); XCTAssertEqual(o.bigBlind, 10); XCTAssertEqual(o.escalationLevel, 0)
        }
        await d.endSession()
    }

    // MARK: - Event stream: private cards routed only to the owner (D-015)

    func testPrivateHoleCardsRoutedToOwnerOnly() async throws {
        let d = driver(seed: 3)
        let mine = await d.events(as: .player(0))
        let spectator = await d.events(as: .spectator)

        var myPrivate: [(Int, [Card])] = []
        var spectatorPrivate = 0
        let collector = Task {
            async let a: Void = { for await e in mine {
                if case let .privateHoleCards(seat, cards) = e.payload { myPrivate.append((seat, cards)) }
            } }()
            async let b: Void = { for await e in spectator {
                if case .privateHoleCards = e.payload { spectatorPrivate += 1 }
            } }()
            _ = await (a, b)
        }
        _ = try await d.playHand()
        await d.endSession()
        _ = await collector.result

        XCTAssertTrue(myPrivate.allSatisfy { $0.0 == 0 }, "a player only receives its OWN private cards")
        XCTAssertTrue(myPrivate.allSatisfy { $0.1.count == 4 }, "Omaha deals four hole cards")
        XCTAssertEqual(myPrivate.count, 1)
        XCTAssertEqual(spectatorPrivate, 0, "a spectator never receives any private cards")
    }

    func testSessionRunsToACompletionAndCanBust() async throws {
        // Small stacks so the session terminates: play until fewer than two remain.
        let d = driver(seed: 314, stacks: [120, 120, 120])
        var hands = 0
        while d.canDealNextHand && hands < 200 { _ = try await d.playHand(); hands += 1 }
        await d.endSession()
        XCTAssertLessThanOrEqual(d.eligiblePlayerCount, 2, "the session drives toward busts and ends")
        XCTAssertGreaterThan(hands, 0)
    }
}
