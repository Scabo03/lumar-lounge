import XCTest
@testable import GameEngine

final class DeckTests: XCTestCase {

    func testNewDeckHasFiftyTwoUniqueCards() {
        let deck = Deck()
        XCTAssertEqual(deck.count, 52)
        XCTAssertEqual(Set(deck.cards).count, 52, "All 52 cards must be distinct.")
    }

    func testNewDeckIsInDeterministicOrder() {
        // A freshly built deck is always identical.
        XCTAssertEqual(Deck().cards, Deck().cards)
        XCTAssertEqual(Deck().cards.first, Card(.two, .spades))
    }

    func testShuffleKeepsFiftyTwoUniqueCards() {
        var deck = Deck()
        deck.shuffle(seed: 42)
        XCTAssertEqual(deck.count, 52)
        XCTAssertEqual(Set(deck.cards).count, 52, "Shuffling must not lose or duplicate cards.")
    }

    func testShuffleActuallyReorders() {
        let ordered = Deck().cards
        var deck = Deck()
        deck.shuffle(seed: 42)
        XCTAssertNotEqual(deck.cards, ordered, "A shuffle should change the order.")
    }

    func testSeededShuffleIsReproducible() {
        var a = Deck(); a.shuffle(seed: 12345)
        var b = Deck(); b.shuffle(seed: 12345)
        XCTAssertEqual(a.cards, b.cards, "Same seed must yield the same ordering.")

        var c = Deck(); c.shuffle(seed: 99999)
        XCTAssertNotEqual(a.cards, c.cards, "Different seeds should (practically) differ.")
    }

    func testDrawRemovesFromTop() {
        var deck = Deck()
        let top = deck.cards.first
        let drawn = deck.draw()
        XCTAssertEqual(drawn, top)
        XCTAssertEqual(deck.count, 51)
        XCTAssertFalse(deck.cards.contains(drawn!), "Drawn card leaves the deck.")
    }

    func testDrainingDeckThenDrawingReturnsNil() {
        var deck = Deck()
        var drawnCount = 0
        while deck.draw() != nil { drawnCount += 1 }
        XCTAssertEqual(drawnCount, 52)
        XCTAssertTrue(deck.isEmpty)
        XCTAssertNil(deck.draw(), "Drawing from an empty deck fails gracefully with nil.")
    }
}
