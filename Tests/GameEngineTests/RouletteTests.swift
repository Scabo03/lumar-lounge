// RouletteTests.swift
// =====================================================================
// D-101 — the roulette engine: layout, odds, the zero rule, determinism.

import XCTest
@testable import GameEngine

final class RouletteTests: XCTestCase {

    // MARK: - Layout and colours

    func testTheWheelIsEuropeanSingleZero() {
        XCTAssertEqual(RouletteLayout.pocketCount, 37, "0…36, one zero, no double zero")
        XCTAssertEqual(RouletteLayout.color(of: 0), .green)
        XCTAssertEqual(RouletteLayout.color(of: 1), .red)
        XCTAssertEqual(RouletteLayout.color(of: 2), .black)
        // The 18 red numbers are exactly the European set.
        XCTAssertEqual(RouletteLayout.redNumbers.count, 18)
        XCTAssertEqual(RouletteLayout.numbers.filter { RouletteLayout.color(of: $0) == .black }.count, 18)
    }

    func testColumnsDozensStreetsCornersAndSixLinesCoverTheRightNumbers() {
        XCTAssertEqual(RouletteLayout.columnNumbers(1), [1,4,7,10,13,16,19,22,25,28,31,34])
        XCTAssertEqual(RouletteLayout.columnNumbers(3), [3,6,9,12,15,18,21,24,27,30,33,36])
        XCTAssertEqual(RouletteLayout.dozenNumbers(2), Array(13...24))
        XCTAssertEqual(RouletteLayout.streetNumbers(row: 1), [1,2,3])
        XCTAssertEqual(RouletteLayout.streetNumbers(row: 12), [34,35,36])
        XCTAssertEqual(RouletteLayout.sixLineNumbers(topRow: 1), [1,2,3,4,5,6])
        XCTAssertEqual(RouletteLayout.cornerNumbers(topLeft: 1), [1,2,4,5])
        XCTAssertEqual(RouletteLayout.cornerNumbers(topLeft: 5), [5,6,8,9])
        // Column 3 has no square to its right, and row 12 has none below.
        XCTAssertNil(RouletteLayout.cornerNumbers(topLeft: 3))
        XCTAssertNil(RouletteLayout.cornerNumbers(topLeft: 34))
    }

    // MARK: - Payout of every bet type, on exact numbers

    /// A win returns the stake PLUS odds×stake. These are the standard European odds.
    func testEveryBetTypePaysItsStandardOdds() {
        let cases: [(RouletteBet, Int, Int)] = [   // (bet, winning pocket, expected returned on 100)
            (.straight(17), 17, 100 * 36),          // 35:1
            (.split(17, 20), 20, 100 * 18),         // 17:1
            (.street(row: 6), 16, 100 * 12),        // 11:1  (row 6 = 16,17,18)
            (.corner(topLeft: 1)!, 5, 100 * 9),     // 8:1
            (.sixLine(topRow: 1), 4, 100 * 6),      // 5:1
            (.column(1), 22, 100 * 3),              // 2:1
            (.dozen(2), 20, 100 * 3),               // 2:1
            (.red, 3, 100 * 2),                     // 1:1
            (.black, 2, 100 * 2),                   // 1:1
            (.even, 4, 100 * 2),                    // 1:1
            (.odd, 7, 100 * 2),                     // 1:1
            (.low, 10, 100 * 2),                    // manque 1:1
            (.high, 30, 100 * 2),                   // passe 1:1
        ]
        for (bet, pocket, expectedReturned) in cases {
            let r = RouletteResolver.resolve(bets: [bet: 100], pocket: pocket)
            XCTAssertEqual(r.totalReturned, expectedReturned, "\(bet.kind) on \(pocket)")
            XCTAssertTrue(r.results[0].didWin)
            XCTAssertEqual(r.net, expectedReturned - 100)
        }
    }

    func testABetThatMissesLosesItsStake() {
        let r = RouletteResolver.resolve(bets: [.red: 100], pocket: 2)  // 2 is black
        XCTAssertEqual(r.totalReturned, 0)
        XCTAssertEqual(r.net, -100)
        XCTAssertEqual(r.results[0].outcome, .lost)
    }

    // MARK: - The zero rule (imposed, D-101)

    func testZeroRefundsTheSimpleEvenMoneyBetsInFull() {
        let bets: [RouletteBet: Int] = [.red: 100, .black: 50, .even: 40, .odd: 30, .low: 20, .high: 10]
        let r = RouletteResolver.resolve(bets: bets, pocket: 0)
        // Every simple even-money bet comes straight back, none lost.
        XCTAssertEqual(r.totalReturned, r.totalStaked, "all even-money stakes returned on zero")
        XCTAssertEqual(r.net, 0)
        XCTAssertTrue(r.zeroRefunded)
        XCTAssertTrue(r.results.allSatisfy { $0.outcome == .refundedOnZero })
    }

    func testZeroDoesNotRefundColumnsDozensOrInsideBetsThatMissIt() {
        let r = RouletteResolver.resolve(bets: [.column(1): 100, .dozen(1): 100, .straight(17): 100],
                                         pocket: 0)
        XCTAssertEqual(r.totalReturned, 0, "columns, dozens and straights that miss zero lose")
        XCTAssertFalse(r.zeroRefunded)
    }

    func testInsideBetsCoveringZeroWinNormally() {
        // A straight on zero, and a split of 0 and 1, both win at their odds when zero hits.
        let r = RouletteResolver.resolve(bets: [.straight(0): 100, .split(0, 1): 50], pocket: 0)
        XCTAssertEqual(r.results.first { $0.bet.kind == .straight }?.returned, 100 * 36)
        XCTAssertEqual(r.results.first { $0.bet.kind == .split }?.returned, 50 * 18)
        XCTAssertFalse(r.zeroRefunded, "these are wins, not refunds")
    }

    // MARK: - Multiple simultaneous bets

    func testMultipleBetsTotalTheStakeAndTheWinningsCorrectly() {
        // Pocket 17 (red, odd, 2nd dozen, 2nd column, high…): several of these pay.
        let bets: [RouletteBet: Int] = [
            .straight(17): 10,     // wins 360
            .red: 50,              // 17 is black? 17 is BLACK → loses
            .odd: 50,              // wins 100
            .dozen(2): 40,         // 13–24 → wins 120
            .low: 30,              // 1–18 → wins 60
            .straight(5): 10,      // loses
        ]
        let r = RouletteResolver.resolve(bets: bets, pocket: 17)
        XCTAssertEqual(RouletteLayout.color(of: 17), .black)
        XCTAssertEqual(r.totalStaked, 190)
        // returned: 360 + 0 + 100 + 120 + 60 + 0 = 640
        XCTAssertEqual(r.totalReturned, 640)
        XCTAssertEqual(r.net, 640 - 190)
        XCTAssertEqual(r.winningResults.count, 4, "four of the six bets paid")
    }

    // MARK: - Determinism

    func testTheWheelIsDeterministicGivenASeed() {
        var a = RouletteWheel(seed: 20260721)
        var b = RouletteWheel(seed: 20260721)
        let seqA = (0..<50).map { _ in a.spin() }
        let seqB = (0..<50).map { _ in b.spin() }
        XCTAssertEqual(seqA, seqB, "same seed → same spins")
        XCTAssertTrue(seqA.allSatisfy { (0...36).contains($0) })
        // A different seed gives a different sequence (overwhelmingly likely).
        var c = RouletteWheel(seed: 99)
        XCTAssertNotEqual(seqA, (0..<50).map { _ in c.spin() })
    }
}
