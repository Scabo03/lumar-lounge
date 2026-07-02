import XCTest
@testable import GameEngine

final class CardTests: XCTestCase {

    func testRankOrdering() {
        XCTAssertTrue(Rank.king > Rank.jack)
        XCTAssertTrue(Rank.ace > Rank.king)
        XCTAssertTrue(Rank.two < Rank.three)
        XCTAssertEqual(Rank.allCases.count, 13)
    }

    func testCardComparesByRankOnly() {
        XCTAssertTrue(Card(.king, .spades) > Card(.jack, .hearts))
        // Same rank, different suit: neither is greater under `<`.
        XCTAssertFalse(Card(.queen, .spades) < Card(.queen, .hearts))
        XCTAssertFalse(Card(.queen, .hearts) < Card(.queen, .spades))
        // ...but they remain distinct values.
        XCTAssertNotEqual(Card(.queen, .spades), Card(.queen, .hearts))
    }

    func testDebugDescriptions() {
        XCTAssertEqual(Card(.ace, .spades).description, "A♠")
        XCTAssertEqual(Card(.king, .hearts).description, "K♥")
        XCTAssertEqual(Card(.ten, .clubs).description, "10♣")
        XCTAssertEqual(Card(.two, .diamonds).description, "2♦")
    }
}
