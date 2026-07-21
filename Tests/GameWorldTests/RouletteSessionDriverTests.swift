// RouletteSessionDriverTests.swift
// =====================================================================
// D-102 — the bet slip (single source of truth), the session driver, and the
// real movement of chips (DEBUG_FREE_PLAY OFF).

import XCTest
@testable import GameWorld
import GameEngine

final class RouletteSessionDriverTests: XCTestCase {

    // MARK: - The bet slip is the single source of truth (D-102)

    func testTouchPlacesTheMinimumAndSwipeStepsByIt() {
        var slip = RouletteBetSlip(minimumBet: 10, maximumBet: 500)
        slip.place(.red)
        XCTAssertEqual(slip.amount(on: .red), 10, "a touch places the minimum")
        slip.increase(.red)
        XCTAssertEqual(slip.amount(on: .red), 20, "a swipe up adds a minimum")
        slip.place(.red)   // touching again does not stack
        XCTAssertEqual(slip.amount(on: .red), 20)
        slip.decrease(.red)
        XCTAssertEqual(slip.amount(on: .red), 10)
        slip.decrease(.red)
        XCTAssertFalse(slip.contains(.red), "swiping down to zero removes the bet")
    }

    /// The point of the single state: adjusting a bet from the TABLE zone or from its
    /// SYMBOL in the register band is the SAME operation on the SAME entry. Both zones
    /// call the same slip, so the two can never diverge.
    func testTableAndBandActOnTheSameStateWithNoDuplicateLogic() {
        var fromTable = RouletteBetSlip(minimumBet: 10, maximumBet: 500)
        var fromBand = RouletteBetSlip(minimumBet: 10, maximumBet: 500)

        // "Table" raises red to 50 by four swipes on the cell; "band" raises it by four
        // swipes on the symbol. Identical API → identical result.
        fromTable.place(.red); fromTable.increase(.red); fromTable.increase(.red); fromTable.increase(.red); fromTable.increase(.red)
        fromBand.place(.red);  fromBand.increase(.red);  fromBand.increase(.red);  fromBand.increase(.red);  fromBand.increase(.red)
        XCTAssertEqual(fromTable, fromBand)
        XCTAssertEqual(fromTable.amount(on: .red), 50)

        // Zeroing from the symbol removes it, exactly as zeroing from the cell would.
        fromBand.setAmount(0, on: .red)
        XCTAssertFalse(fromBand.contains(.red))
    }

    func testTheSlipTotalsWhatIsAtStakeAndOrdersByFrequency() {
        var slip = RouletteBetSlip(minimumBet: 10, maximumBet: 500)
        slip.setAmount(50, on: .red)
        slip.setAmount(30, on: .straight(17))
        slip.setAmount(20, on: .dozen(1))
        XCTAssertEqual(slip.totalStaked, 100)
        // Frequency order: red (0) before dozen (2) before straight (4).
        XCTAssertEqual(slip.orderedBets.map { $0.bet.kind }, [.red, .dozen, .straight])
    }

    func testAmountsAreClampedToThePerBetCeiling() {
        var slip = RouletteBetSlip(minimumBet: 10, maximumBet: 100)
        slip.setAmount(1000, on: .red)
        XCTAssertEqual(slip.amount(on: .red), 100, "no bet exceeds the table maximum")
    }

    // MARK: - The driver, with real chips (free play OFF)

    @MainActor
    private func account(_ chips: Int) -> PlayerAccount {
        PlayerAccount(store: InMemoryChipsStore(chips: chips), freePlay: false)
    }

    func testARoundDeductsTheStakeAndPaysTheReturn() async throws {
        let provider = ScriptedRouletteActionProvider([[.straight(7): 10, .red: 20]])
        // Seed chosen so the first spin is known; assert against the actual result.
        let driver = RouletteSessionDriver(chips: 1000, rules: .riverwood, provider: provider, seed: 4242)
        let outcome = try await driver.playRound()
        let r = try XCTUnwrap(outcome)

        // Chips end at start - staked + returned, exactly.
        XCTAssertEqual(driver.chips, 1000 - r.resolution.totalStaked + r.resolution.totalReturned)
        XCTAssertEqual(r.resolution.totalStaked, 30)
        await driver.endSession()
    }

    func testChipsAreConservedAcrossManyRoundsInTheWallet() async throws {
        // A full economic run with FREE PLAY OFF: buy in, play, cash out — the wallet
        // moves by exactly the session's net.
        let acct = await account(5000)
        let buyIn = RouletteTableRules.riverwood.buyIn
        _ = await MainActor.run { acct.buyIn(buyIn) }
        let startWalletAfterBuyIn = await MainActor.run { acct.chips }   // 5000 - 1000

        let provider = ScriptedRouletteActionProvider(Array(repeating: [.red: 10, .black: 10], count: 20))
        let driver = RouletteSessionDriver(chips: buyIn, rules: .riverwood, provider: provider, seed: 77)
        _ = try await driver.run(maxRounds: 20)
        await driver.endSession()

        await MainActor.run { acct.cashOut(driver.chips) }
        let finalWallet = await MainActor.run { acct.chips }
        // Betting red AND black each round: one always wins (+10), the other loses (−10),
        // net 0 — UNLESS zero hits, which refunds both (still net 0). So the table stack
        // returns intact and the wallet is exactly back to where it started.
        XCTAssertEqual(finalWallet, startWalletAfterBuyIn + driver.chips)
        XCTAssertEqual(finalWallet, 5000, "red+black each round conserves the stack")
    }

    func testZeroRefundsTheEvenMoneyBetsThroughTheDriver() async throws {
        // Find a seed whose first spin is zero, then verify the refund reaches the chips.
        var zeroSeed: UInt64?
        for candidate in UInt64(1)...2000 {
            var w = RouletteWheel(seed: candidate)
            if w.spin() == 0 { zeroSeed = candidate; break }
        }
        let seed = try XCTUnwrap(zeroSeed, "a zero must occur within the search")
        let provider = ScriptedRouletteActionProvider([[.red: 100, .even: 50]])
        let driver = RouletteSessionDriver(chips: 1000, rules: .riverwood, provider: provider, seed: seed)
        let played = try await driver.playRound()
        let r = try XCTUnwrap(played)
        XCTAssertEqual(r.resolution.winningPocket, 0)
        XCTAssertTrue(r.resolution.zeroRefunded)
        XCTAssertEqual(driver.chips, 1000, "zero returns the even-money stakes in full")
        await driver.endSession()
    }

    func testTheSessionIsDeterministicGivenASeed() async throws {
        func run() async throws -> [Int] {
            let provider = ScriptedRouletteActionProvider(Array(repeating: [.red: 10], count: 30))
            let driver = RouletteSessionDriver(chips: 1000, rules: .riverwood, provider: provider, seed: 123)
            let outcomes = try await driver.run(maxRounds: 30)
            await driver.endSession()
            return outcomes.map { $0.resolution.winningPocket }
        }
        let a = try await run()
        let b = try await run()
        XCTAssertEqual(a, b, "same seed → same spins")
    }

    func testLeavingReturnsNilAndWindsUpTheSession() async throws {
        let human = HumanRouletteActionProvider()
        let driver = RouletteSessionDriver(chips: 1000, rules: .riverwood, provider: human, seed: 1)
        await human.abandon()
        let outcome = try await driver.playRound()
        XCTAssertNil(outcome, "abandoning declines the bet, ending the round cleanly")
        await driver.endSession()
    }
}
