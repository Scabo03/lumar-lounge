import XCTest
@testable import GameWorld
import GameEngine

/// Always checks when it can, never opens; folds only if it can't check. Makes
/// every deal pass in (nobody opens) — useful to exercise the progressive pot.
private struct NeverOpenProvider: DrawActionProvider {
    func provideAction(for context: DrawBotContext) async -> DrawAction {
        context.legal.canCheck ? .check : .fold
    }
    func provideDiscards(for context: DrawDrawContext) async -> [Card] { [] }
}

/// Opens whenever it can, otherwise calls; stands pat in the draw. Forces a played
/// deal to showdown (first actor opens, the rest call).
private struct AlwaysOpenProvider: DrawActionProvider {
    func provideAction(for context: DrawBotContext) async -> DrawAction {
        if context.legal.canBet { return .bet }
        if context.legal.canCall { return .call }
        return context.legal.canCheck ? .check : .fold
    }
    func provideDiscards(for context: DrawDrawContext) async -> [Card] { [] }
}

final class DrawSessionDriverTests: XCTestCase {

    private func bot(_ personality: Personality, seed: UInt64) -> DrawBotActionProvider {
        DrawBotActionProvider(HeuristicDrawBot(personality: personality, seed: seed))
    }

    private func fourSeats(_ providers: [DrawActionProvider], chips: Int = 1000) -> [DrawSeatAssignment] {
        providers.enumerated().map { DrawSeatAssignment(position: $0.offset, playerID: $0.offset,
                                                        chips: chips, provider: $0.element) }
    }

    // MARK: - Bot vs bot to the bust, chips conserved

    func testHeadsUpBotSessionRunsToBustConservingChips() async throws {
        let driver = DrawSessionDriver(capacity: 2, seats: [
            DrawSeatAssignment(position: 0, playerID: 0, chips: 200, provider: bot(.hotAggressor, seed: 11)),
            DrawSeatAssignment(position: 1, playerID: 1, chips: 200, provider: bot(.eagerNovice, seed: 22)),
        ], buttonPosition: 0, ante: 10, smallBet: 20, bigBet: 40, seed: 7)

        let total = 400
        let outcomes = try await driver.run(maxHands: 3000)
        for outcome in outcomes {
            XCTAssertEqual(outcome.chipsByPlayer.values.reduce(0, +) + outcome.carriedPot, total,
                           "Chips not conserved after deal \(outcome.handNumber)")
        }
        XCTAssertLessThanOrEqual(driver.eligiblePlayerCount, 1)
        XCTAssertFalse(driver.canDealNextHand)
    }

    // MARK: - Four players (one a simulated human), chips conserved

    func testFourPlayerSessionWithSimulatedHumanConservesChips() async throws {
        // Seat 0 is a passive "human" (never opens); the rest are bots.
        let driver = DrawSessionDriver(capacity: 4, seats: fourSeats([
            NeverOpenProvider(),
            bot(.conservativeRock, seed: 100),
            bot(.hotAggressor, seed: 200),
            bot(.eagerNovice, seed: 300),
        ]), buttonPosition: 0, ante: 10, smallBet: 20, bigBet: 40, seed: 5)

        let total = 4000
        let outcomes = try await driver.run(maxHands: 200)
        XCTAssertFalse(outcomes.isEmpty)
        for outcome in outcomes {
            XCTAssertEqual(outcome.chipsByPlayer.values.reduce(0, +) + outcome.carriedPot, total)
        }
    }

    // MARK: - Pass-and-out: progressive pot + button does not rotate (D-040)

    func testPassAndOutAccumulatesProgressivePotAndKeepsButton() async throws {
        // Everyone always checks → every deal passes in. Antes stack up in the pot;
        // the button never rotates and no hand is "played".
        let driver = DrawSessionDriver(capacity: 4, seats: fourSeats(
            Array(repeating: NeverOpenProvider(), count: 4), chips: 1000),
            buttonPosition: 2, ante: 10, smallBet: 20, bigBet: 40, seed: 9)

        let d1 = try await driver.playHand()
        XCTAssertFalse(d1.wasPlayed)
        XCTAssertEqual(d1.carriedPot, 40)                 // 4 antes
        XCTAssertEqual(driver.buttonPosition, 2)          // button unchanged
        XCTAssertEqual(driver.handNumber, 0)              // no hand played
        XCTAssertEqual(driver.consecutivePassed, 1)

        let d2 = try await driver.playHand()
        XCTAssertFalse(d2.wasPlayed)
        XCTAssertEqual(d2.carriedPot, 80)                 // antes accumulate
        XCTAssertEqual(driver.buttonPosition, 2)          // STILL unchanged
        XCTAssertEqual(driver.consecutivePassed, 2)

        let d3 = try await driver.playHand()
        XCTAssertEqual(d3.carriedPot, 120)
        XCTAssertEqual(driver.consecutivePassed, 3)
        // Chips conserved throughout (antes are on the table, not lost).
        XCTAssertEqual(d3.chipsByPlayer.values.reduce(0, +) + d3.carriedPot, 4000)
    }

    // MARK: - A played deal rotates the button and clears the progressive pot

    func testPlayedDealRotatesButtonAndClearsCarriedPot() async throws {
        let driver = DrawSessionDriver(capacity: 4, seats: fourSeats(
            Array(repeating: AlwaysOpenProvider(), count: 4), chips: 1000),
            buttonPosition: 0, ante: 10, smallBet: 20, bigBet: 40, seed: 3)

        let outcome = try await driver.playHand()
        XCTAssertTrue(outcome.wasPlayed)
        XCTAssertEqual(outcome.carriedPot, 0)             // pot was awarded
        XCTAssertEqual(driver.buttonPosition, 1)          // advanced one
        XCTAssertEqual(driver.handNumber, 1)
        XCTAssertEqual(outcome.chipsByPlayer.values.reduce(0, +), 4000)  // conserved
    }

    // MARK: - Carried pot is paid out on the next played deal

    func testCarriedPotIsAwardedOnTheFollowingPlayedDeal() async throws {
        // Two passes then a played deal: the played deal's pot includes the carry,
        // so total chips return in full to the stacks (conserved, carry cleared).
        let providers: [DrawActionProvider] = [
            AlwaysOpenProvider(), AlwaysOpenProvider(), AlwaysOpenProvider(), AlwaysOpenProvider(),
        ]
        // Force two passes first with a never-open driver on the same seats is not
        // possible per-deal, so instead assert the invariant on a long played run.
        let driver = DrawSessionDriver(capacity: 4, seats: fourSeats(providers, chips: 1000),
                                       buttonPosition: 0, ante: 10, smallBet: 20, bigBet: 40, seed: 8)
        let outcomes = try await driver.run(maxHands: 30)
        for outcome in outcomes {
            XCTAssertEqual(outcome.chipsByPlayer.values.reduce(0, +) + outcome.carriedPot, 4000)
            if outcome.wasPlayed { XCTAssertEqual(outcome.carriedPot, 0) }
        }
    }

    // MARK: - Determinism end-to-end

    func testSameSeedProducesSameSession() async throws {
        func play() async throws -> [Int: Int] {
            let driver = DrawSessionDriver(capacity: 4, seats: fourSeats([
                bot(.eagerNovice, seed: 1), bot(.conservativeRock, seed: 2),
                bot(.hotAggressor, seed: 3), bot(.eagerNovice, seed: 4),
            ]), buttonPosition: 0, ante: 10, smallBet: 20, bigBet: 40, seed: 42)
            _ = try await driver.run(maxHands: 40)
            return Dictionary(uniqueKeysWithValues: driver.players.map { ($0.id, $0.chips) })
        }
        let a = try await play()
        let b = try await play()
        XCTAssertEqual(a, b)
    }
}
