import XCTest
@testable import GameWorld
import GameEngine

/// A deterministic, always-legal provider that just checks/calls (a stand-in
/// for a passive human, useful for determinism and wiring tests).
private struct PassiveProvider: ActionProvider {
    func provideAction(for context: BotContext) async -> Action {
        if context.legal.canCheck { return .check }
        if context.legal.canCall { return .call }
        return .fold
    }
}

final class SessionDriverTests: XCTestCase {

    private func bot(_ personality: Personality, seed: UInt64) -> BotActionProvider {
        BotActionProvider(HeuristicBot(personality: personality, seed: seed, equitySamples: 40))
    }

    // MARK: - Two bots to the bust

    func testTwoBotSessionRunsToBustConservingChips() async throws {
        let driver = SessionDriver(capacity: 2, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 100, provider: bot(.hotAggressor, seed: 11)),
            SeatAssignment(position: 1, playerID: 1, chips: 100, provider: bot(.eagerNovice, seed: 22)),
        ], buttonPosition: 0, smallBlind: 5, bigBlind: 10, seed: 7)

        let total = 200
        let outcomes = try await driver.run(maxHands: 2000)

        // Chips are conserved after every single hand.
        for outcome in outcomes {
            XCTAssertEqual(outcome.chipsByPlayer.values.reduce(0, +), total,
                           "Chips not conserved after hand \(outcome.handNumber)")
        }
        // The session ended because someone busted (only one player has chips).
        XCTAssertEqual(driver.eligiblePlayerCount, 1)
        XCTAssertFalse(driver.canDealNextHand)
        let winner = driver.players.first { $0.chips > 0 }!
        XCTAssertEqual(winner.chips, total)
        let loser = driver.players.first { $0.chips == 0 }!
        XCTAssertEqual(loser.status, .bustedOut)
    }

    // MARK: - Three players, one busts mid-session

    func testThreePlayersOneBustsAndSessionContinues() async throws {
        // A short stack (player 1) will bust quickly against two deep stacks.
        let driver = SessionDriver(capacity: 3, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 1000, provider: bot(.hotAggressor, seed: 1)),
            SeatAssignment(position: 1, playerID: 1, chips: 30, provider: bot(.eagerNovice, seed: 2)),
            SeatAssignment(position: 2, playerID: 2, chips: 1000, provider: bot(.hotAggressor, seed: 3)),
        ], buttonPosition: 0, smallBlind: 5, bigBlind: 10, seed: 5)

        let total = 2030
        var sawBust = false
        let outcomes = try await driver.run(maxHands: 200) { _ in true }

        for outcome in outcomes {
            XCTAssertEqual(outcome.chipsByPlayer.values.reduce(0, +), total)
            if outcome.bustedThisHand.contains(1) { sawBust = true }
            // Once player 1 has busted, it is never dealt in again.
            if sawBust && driver.player(1)?.chips == 0 {
                // handled below by the participant check on later hands
            }
        }
        XCTAssertTrue(sawBust, "The short stack should have busted")
        XCTAssertEqual(driver.player(1)?.status, .bustedOut)

        // After the bust, the two survivors keep playing heads-up.
        let afterBust = outcomes.drop { !$0.bustedThisHand.contains(1) }.dropFirst()
        for outcome in afterBust {
            XCTAssertFalse(outcome.participantIDs.contains(1), "Busted player must not be dealt in")
            XCTAssertEqual(Set(outcome.participantIDs), [0, 2])
        }
    }

    // MARK: - Button rotation with dead/busted seats

    func testButtonRotatesByPositionAndSkipsBustedSeats() async throws {
        let capacity = 3
        let initialButton = 0
        let driver = SessionDriver(capacity: capacity, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 1000, provider: bot(.hotAggressor, seed: 1)),
            SeatAssignment(position: 1, playerID: 1, chips: 25, provider: bot(.eagerNovice, seed: 2)),
            SeatAssignment(position: 2, playerID: 2, chips: 1000, provider: bot(.hotAggressor, seed: 3)),
        ], buttonPosition: initialButton, smallBlind: 5, bigBlind: 10, seed: 9)

        let outcomes = try await driver.run(maxHands: 60)

        var bustedSoFar = Set<Int>()
        for outcome in outcomes {
            // Button advances exactly one physical position per hand (dead button).
            XCTAssertEqual(outcome.buttonPosition, (initialButton + outcome.handNumber) % capacity)
            // No already-busted player is ever dealt in again.
            XCTAssertTrue(Set(outcome.participantIDs).isDisjoint(with: bustedSoFar),
                          "A busted player was dealt in on hand \(outcome.handNumber)")
            bustedSoFar.formUnion(outcome.bustedThisHand)
        }
        XCTAssertTrue(bustedSoFar.contains(1), "Expected the short stack to bust during the run")
    }

    // MARK: - Determinism end to end

    func testEndToEndDeterminism() async throws {
        func runSession() async throws -> [[Int: Int]] {
            let driver = SessionDriver(capacity: 3, seats: [
                SeatAssignment(position: 0, playerID: 0, chips: 500, provider: bot(.conservativeRock, seed: 1)),
                SeatAssignment(position: 1, playerID: 1, chips: 500, provider: PassiveProvider()),
                SeatAssignment(position: 2, playerID: 2, chips: 500, provider: bot(.hotAggressor, seed: 3)),
            ], buttonPosition: 0, smallBlind: 5, bigBlind: 10, seed: 4242)
            let outcomes = try await driver.run(maxHands: 40)
            return outcomes.map { $0.chipsByPlayer }
        }
        let a = try await runSession()
        let b = try await runSession()
        XCTAssertEqual(a, b, "Same config + seeds + (passive) actions must reproduce exactly")
        XCTAssertFalse(a.isEmpty)
    }

    // MARK: - New player joins between hands

    func testNewPlayerCanJoinBetweenHands() async throws {
        let driver = SessionDriver(capacity: 3, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 1000, provider: bot(.conservativeRock, seed: 1)),
            SeatAssignment(position: 1, playerID: 1, chips: 1000, provider: bot(.conservativeRock, seed: 2)),
        ], buttonPosition: 0, smallBlind: 5, bigBlind: 10, seed: 3)

        _ = try await driver.playHand()
        XCTAssertNil(driver.player(2))

        try driver.addPlayer(id: 2, chips: 1000, at: 2, provider: bot(.hotAggressor, seed: 9))
        XCTAssertEqual(driver.player(2)?.chips, 1000)

        let outcome = try await driver.playHand()
        XCTAssertTrue(outcome.participantIDs.contains(2), "The newcomer should be dealt into the next hand")
        // Chips conserved across the join (now three players of 1000 each minus nothing lost off-table).
        XCTAssertEqual(outcome.chipsByPlayer.values.reduce(0, +), 3000)
    }

    // MARK: - Human suspend / resume

    func testHumanActionSuspendsAndResumesAndBlocksJoins() async throws {
        let human = HumanActionProvider()
        let driver = SessionDriver(capacity: 3, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 1000, provider: human),
            SeatAssignment(position: 1, playerID: 1, chips: 1000, provider: bot(.conservativeRock, seed: 1)),
        ], buttonPosition: 0, smallBlind: 5, bigBlind: 10, seed: 8)

        // Player 0 (the human) is the heads-up button/small blind and acts first.
        let handTask = Task { try await driver.playHand() }

        // Wait until the driver is suspended awaiting the human.
        var spins = 0
        while await !human.isWaiting {
            await Task.yield()
            spins += 1
            if spins > 1_000_000 { XCTFail("The human was never asked to act"); break }
        }

        // The hand is genuinely in progress and structural changes are blocked.
        XCTAssertTrue(driver.isHandInProgress)
        XCTAssertThrowsError(try driver.addPlayer(id: 2, chips: 500, at: 2, provider: human)) { error in
            XCTAssertEqual(error as? SessionError, .handInProgress)
        }

        // The human folds; the driver resumes and the hand completes.
        await human.submit(.fold)
        let outcome = try await handTask.value

        XCTAssertFalse(outcome.result.wentToShowdown, "A fold ends the hand without a showdown")
        XCTAssertEqual(driver.chips(of: 1), 1005, "The bot (BB) wins the small blind")
        XCTAssertEqual(driver.chips(of: 0), 995)
        XCTAssertFalse(driver.isHandInProgress)
    }

    // MARK: - Guards

    func testCannotDealWithFewerThanTwoPlayers() async throws {
        let driver = SessionDriver(capacity: 2, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 100, provider: bot(.conservativeRock, seed: 1)),
            SeatAssignment(position: 1, playerID: 1, chips: 100, provider: bot(.conservativeRock, seed: 2)),
        ], buttonPosition: 0, smallBlind: 5, bigBlind: 10, seed: 1)
        try driver.removePlayer(id: 1)
        XCTAssertFalse(driver.canDealNextHand)
        do {
            _ = try await driver.playHand()
            XCTFail("Expected notEnoughPlayers")
        } catch {
            XCTAssertEqual(error as? SessionError, .notEnoughPlayers)
        }
    }
}
