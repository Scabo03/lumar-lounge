import XCTest
@testable import GameWorld

/// The Fast table's decisive-hand boost (D-037): after N consecutive hands with no
/// pre-flop fold, the next hand is decisive; a fold breaks the streak; dealing the
/// decisive hand restarts the counter.
final class DecisiveHandBoostTests: XCTestCase {

    func testStreakBuildsToTheThreshold() {
        let boost = DecisiveHandBoost(threshold: 3)
        XCTAssertFalse(boost.isNextHandDecisive)
        boost.recordHand(anyFoldPreflop: false)   // 1
        boost.recordHand(anyFoldPreflop: false)   // 2
        XCTAssertFalse(boost.isNextHandDecisive, "not yet at the threshold")
        boost.recordHand(anyFoldPreflop: false)   // 3
        XCTAssertTrue(boost.isNextHandDecisive, "three no-fold hands → next is decisive")
    }

    func testAnyPreflopFoldResetsTheStreak() {
        let boost = DecisiveHandBoost(threshold: 3)
        boost.recordHand(anyFoldPreflop: false)
        boost.recordHand(anyFoldPreflop: false)
        boost.recordHand(anyFoldPreflop: true)    // someone folded pre-flop → reset
        XCTAssertEqual(boost.streak, 0)
        XCTAssertFalse(boost.isNextHandDecisive)
    }

    func testDealingTheDecisiveHandRestartsTheCounter() {
        let boost = DecisiveHandBoost(threshold: 3)
        for _ in 0..<3 { boost.recordHand(anyFoldPreflop: false) }
        XCTAssertTrue(boost.isNextHandDecisive)
        boost.consumeDecisiveHand()
        XCTAssertFalse(boost.isNextHandDecisive)
        XCTAssertEqual(boost.streak, 0)
    }
}
