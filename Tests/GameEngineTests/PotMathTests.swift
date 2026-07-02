import XCTest
@testable import GameEngine

final class PotMathTests: XCTestCase {

    private func contrib(_ id: Int, _ amount: Int, folded: Bool = false) -> PotMath.Contribution {
        PotMath.Contribution(id: id, amount: amount, folded: folded)
    }

    // MARK: - Side pots

    func testSinglePotWhenEveryoneContributesEqually() {
        let pots = PotMath.sidePots(from: [contrib(0, 100), contrib(1, 100), contrib(2, 100)])
        XCTAssertEqual(pots, [Pot(amount: 300, eligibleSeatIDs: [0, 1, 2])])
    }

    func testTwoAllInStacksProduceMainAndSidePot() {
        // A all-in 50, B and C in for 100 each.
        let pots = PotMath.sidePots(from: [contrib(0, 50), contrib(1, 100), contrib(2, 100)])
        XCTAssertEqual(pots, [
            Pot(amount: 150, eligibleSeatIDs: [0, 1, 2]), // main: 50 × 3
            Pot(amount: 100, eligibleSeatIDs: [1, 2]),    // side: 50 × 2
        ])
    }

    func testThreeDistinctAllInLevels() {
        // 30 / 60 / 100.
        let pots = PotMath.sidePots(from: [contrib(0, 30), contrib(1, 60), contrib(2, 100)])
        XCTAssertEqual(pots, [
            Pot(amount: 90, eligibleSeatIDs: [0, 1, 2]), // 30 × 3
            Pot(amount: 60, eligibleSeatIDs: [1, 2]),    // 30 × 2
            Pot(amount: 40, eligibleSeatIDs: [2]),       // 40 × 1 (uncalled, returns to C)
        ])
    }

    func testFoldedContributorAddsChipsButCannotWin() {
        // A folded after putting in 100; B in 100; C all-in 60.
        let pots = PotMath.sidePots(from: [contrib(0, 100, folded: true), contrib(1, 100), contrib(2, 60)])
        XCTAssertEqual(pots, [
            Pot(amount: 180, eligibleSeatIDs: [1, 2]), // 60 × 3, A not eligible
            Pot(amount: 80, eligibleSeatIDs: [1]),     // 40 × 2, only B eligible
        ])
    }

    func testNoContributionsProducesNoPots() {
        XCTAssertEqual(PotMath.sidePots(from: [contrib(0, 0), contrib(1, 0)]), [])
    }

    // MARK: - Distribution & odd chip

    func testEvenSplit() {
        XCTAssertEqual(PotMath.distribute(200, toWinnersInPriorityOrder: [0, 1]), [0: 100, 1: 100])
    }

    func testOddChipGoesToFirstInPriorityOrder() {
        XCTAssertEqual(PotMath.distribute(201, toWinnersInPriorityOrder: [0, 1]), [0: 101, 1: 100])
    }

    func testRemainderSpreadAcrossThreeWinners() {
        // 10 / 3 = 3 remainder 1 → first winner gets the extra chip.
        XCTAssertEqual(PotMath.distribute(10, toWinnersInPriorityOrder: [3, 7, 1]), [3: 4, 7: 3, 1: 3])
        // 11 / 3 = 3 remainder 2 → first two winners get an extra chip each.
        XCTAssertEqual(PotMath.distribute(11, toWinnersInPriorityOrder: [3, 7, 1]), [3: 4, 7: 4, 1: 3])
    }

    func testSingleWinnerTakesAll() {
        XCTAssertEqual(PotMath.distribute(175, toWinnersInPriorityOrder: [5]), [5: 175])
    }
}
