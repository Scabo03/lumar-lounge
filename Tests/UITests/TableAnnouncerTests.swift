import XCTest
@testable import UI
import GameWorld
import GameEngine

/// Pure tests of the semantic event→speech mapping (no localization needed).
final class TableAnnouncerTests: XCTestCase {

    private let names = [0: "Novice", 1: "Rock", 2: "Aggressor"]

    func testHandBeganMapsToHandStartWithOneBasedNumberAndButtonName() {
        let payload = EventPayload.handBegan(handNumber: 0, buttonPosition: 0, buttonSeatID: 2,
                                             smallBlindSeatID: 0, bigBlindSeatID: 1,
                                             smallBlind: 10, bigBlind: 20, seats: [])
        XCTAssertEqual(TableAnnouncer.spoken(for: payload, names: names),
                       .handStart(handNumber: 1, buttonName: "Aggressor"))
    }

    func testActionMapsToActedWithWho() {
        let payload = EventPayload.playerActed(seatID: 1, action: .raised(to: 40, amount: 40, isAllIn: false))
        XCTAssertEqual(TableAnnouncer.spoken(for: payload, names: names),
                       .acted(who: "Rock", action: .raised(to: 40, amount: 40, isAllIn: false)))
    }

    func testBlindMapsWithNameAndAmount() {
        let payload = EventPayload.blindPosted(seatID: 0, blind: .small, amount: 10, isAllIn: false)
        XCTAssertEqual(TableAnnouncer.spoken(for: payload, names: names),
                       .blind(kind: .small, who: "Novice", amount: 10))
    }

    func testStreetAndShownAndPotMap() {
        let flop = [Card(.ace, .spades), Card(.king, .hearts), Card(.two, .clubs)]
        XCTAssertEqual(TableAnnouncer.spoken(for: .streetOpened(street: .flop, communityCards: flop), names: names),
                       .street(.flop, cards: flop))

        let hole = [Card(.ace, .spades), Card(.ace, .diamonds)]
        XCTAssertEqual(TableAnnouncer.spoken(for: .handShown(seatID: 2, holeCards: hole, category: .pair, bestFive: hole), names: names),
                       .shown(who: "Aggressor", cards: hole, category: .pair))

        XCTAssertEqual(TableAnnouncer.spoken(for: .potAwarded(potIndex: 0, amount: 120, winnerSeatIDs: [1, 2]), names: names),
                       .potAwarded(amount: 120, winners: ["Rock", "Aggressor"]))
    }

    func testSilentEventsReturnNil() {
        XCTAssertNil(TableAnnouncer.spoken(for: .holeCardsDealt(seatID: 0), names: names))
        XCTAssertNil(TableAnnouncer.spoken(for: .privateHoleCards(seatID: 0, cards: []), names: names))
        XCTAssertNil(TableAnnouncer.spoken(for: .handEnded(handNumber: 0, wentToShowdown: false, board: [], payouts: [:], chips: [:]), names: names))
        XCTAssertNil(TableAnnouncer.spoken(for: .sessionEnded(reason: .stopped), names: names))
    }

    func testUnknownSeatFallsBackToItsID() {
        let payload = EventPayload.playerActed(seatID: 9, action: .folded)
        XCTAssertEqual(TableAnnouncer.spoken(for: payload, names: names),
                       .acted(who: "9", action: .folded))
    }

    // Card symbol formatting is pure and localization-free.
    func testCardSymbols() {
        XCTAssertEqual(CardText.symbol(Card(.ace, .spades)), "A♠")
        XCTAssertEqual(CardText.symbol(Card(.ten, .hearts)), "10♥")
        XCTAssertEqual(CardText.symbols([Card(.two, .clubs), Card(.king, .diamonds)]), "2♣ K♦")
    }
}
