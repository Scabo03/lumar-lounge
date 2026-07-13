import XCTest
@testable import GameWorld

/// The reusable hands-count stake-escalation primitive (D-064). Purely a function of
/// the count of PLAYED hands — never a clock (accessibility rule, CONVENTIONS §4).
final class StakeEscalationTests: XCTestCase {

    func testDisabledByDefault() {
        let e = StakeEscalation.none
        XCTAssertEqual(e.multiplier(afterPlayedHands: 1000), 1.0)
        XCTAssertEqual(e.level(afterPlayedHands: 1000), 0)
        XCTAssertEqual(e.blinds(baseSmall: 5, baseBig: 10, afterPlayedHands: 1000).big, 10)
    }

    func testLevelAndMultiplierStepEveryInterval() {
        let e = StakeEscalation(interval: 10, factor: 1.5)
        XCTAssertEqual(e.level(afterPlayedHands: 0), 0)
        XCTAssertEqual(e.level(afterPlayedHands: 9), 0)
        XCTAssertEqual(e.level(afterPlayedHands: 10), 1)
        XCTAssertEqual(e.level(afterPlayedHands: 25), 2)
        XCTAssertEqual(e.multiplier(afterPlayedHands: 10), 1.5, accuracy: 1e-9)
        XCTAssertEqual(e.multiplier(afterPlayedHands: 20), 2.25, accuracy: 1e-9)
    }

    func testBlindsEscalateKeepingOrder() {
        let e = StakeEscalation(interval: 3, factor: 2)
        XCTAssertEqual(e.blinds(baseSmall: 5, baseBig: 10, afterPlayedHands: 0).small, 5)
        XCTAssertEqual(e.blinds(baseSmall: 5, baseBig: 10, afterPlayedHands: 3).small, 10)
        XCTAssertEqual(e.blinds(baseSmall: 5, baseBig: 10, afterPlayedHands: 3).big, 20)
        XCTAssertEqual(e.blinds(baseSmall: 5, baseBig: 10, afterPlayedHands: 6).big, 40)
        // small ≤ big always holds after rounding.
        let b = StakeEscalation(interval: 1, factor: 1.5).blinds(baseSmall: 5, baseBig: 6, afterPlayedHands: 1)
        XCTAssertLessThanOrEqual(b.small, b.big)
    }

    func testGuardsClampBadInput() {
        XCTAssertEqual(StakeEscalation(interval: -5, factor: 0.2).multiplier(afterPlayedHands: 100), 1.0)
    }
}
