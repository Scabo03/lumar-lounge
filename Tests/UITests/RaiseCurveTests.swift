import XCTest
@testable import UI

/// Pure tests of the progressive raise curve (D-020) and the raise box state.
final class RaiseCurveTests: XCTestCase {

    // A wide window so the curve is exercised unclamped.
    private let min = 40
    private let max = 1_000_000

    func testStartsAtMinimum() {
        XCTAssertEqual(RaiseCurve.value(clicks: 0, min: min, max: max), 40)
    }

    func testFirstThreeClicksAddTen() {
        XCTAssertEqual(RaiseCurve.value(clicks: 1, min: min, max: max), 50)
        XCTAssertEqual(RaiseCurve.value(clicks: 2, min: min, max: max), 60)
        XCTAssertEqual(RaiseCurve.value(clicks: 3, min: min, max: max), 70)
    }

    func testNextThreeClicksAddTwentyFive() {
        XCTAssertEqual(RaiseCurve.value(clicks: 4, min: min, max: max), 95)
        XCTAssertEqual(RaiseCurve.value(clicks: 5, min: min, max: max), 120)
        XCTAssertEqual(RaiseCurve.value(clicks: 6, min: min, max: max), 145)
    }

    func testNextTwoClicksAddFifty() {
        XCTAssertEqual(RaiseCurve.value(clicks: 7, min: min, max: max), 195)
        XCTAssertEqual(RaiseCurve.value(clicks: 8, min: min, max: max), 245)
    }

    func testNextTwoClicksAddHundred() {
        XCTAssertEqual(RaiseCurve.value(clicks: 9, min: min, max: max), 345)
        XCTAssertEqual(RaiseCurve.value(clicks: 10, min: min, max: max), 445)
    }

    func testThenEachClickAddsTwoFifty() {
        XCTAssertEqual(RaiseCurve.value(clicks: 11, min: min, max: max), 695)
        XCTAssertEqual(RaiseCurve.value(clicks: 12, min: min, max: max), 945)
        XCTAssertEqual(RaiseCurve.value(clicks: 13, min: min, max: max), 1195)
    }

    func testValueIsClampedToMax() {
        XCTAssertEqual(RaiseCurve.value(clicks: 100, min: 40, max: 100), 100)
        XCTAssertEqual(RaiseCurve.value(clicks: 3, min: 40, max: 65), 65) // 70 clamped to 65
    }

    func testClicksToMax() {
        // 40 → 50 → 60 → 70 → 95 → 120(≥100): 5 clicks.
        XCTAssertEqual(RaiseCurve.clicksToMax(min: 40, max: 100), 5)
        XCTAssertEqual(RaiseCurve.clicksToMax(min: 40, max: 40), 0)
    }

    // MARK: - RaiseBoxState

    func testBoxStepUpAndDown() {
        var box = RaiseBoxState(minTo: 40, maxTo: 1000, isBet: false)
        XCTAssertEqual(box.value, 40)
        XCTAssertTrue(box.isAtMin)
        box.increase(); XCTAssertEqual(box.value, 50)
        box.increase(); XCTAssertEqual(box.value, 60)
        box.decrease(); XCTAssertEqual(box.value, 50)
        box.decrease(); XCTAssertEqual(box.value, 40)
        box.decrease(); XCTAssertEqual(box.value, 40) // never below min
        XCTAssertTrue(box.isAtMin)
    }

    func testBoxAllInAndStepDownFromMax() {
        var box = RaiseBoxState(minTo: 40, maxTo: 100, isBet: false)
        box.toMax()
        XCTAssertEqual(box.value, 100)
        XCTAssertTrue(box.isAtMax)
        box.increase(); XCTAssertEqual(box.value, 100) // cannot exceed all-in
        box.decrease(); XCTAssertEqual(box.value, 95)  // one step below max
        XCTAssertFalse(box.isAtMax)
    }
}
