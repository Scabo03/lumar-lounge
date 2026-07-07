import XCTest
@testable import UI
import GameWorld
import GameEngine

/// Characterises the NEW VoiceOver rules (strategy C, D-028): the pure mapping
/// speaks only what is personal to the human player and stays silent on
/// everything institutional (croupier's job) or belonging to an opponent.
final class TableAnnouncerTests: XCTestCase {

    private let hero = 0

    // MARK: - Personal moments → spoken

    func testHeroHoleCardsAreSpoken() {
        let cards = [Card(.ace, .spades), Card(.king, .hearts)]
        XCTAssertEqual(TableAnnouncer.spoken(for: .privateHoleCards(seatID: hero, cards: cards), heroSeatID: hero),
                       .heroCards(cards))
    }

    func testHeroOwnActionIsSpokenAsConfirmation() {
        let payload = EventPayload.playerActed(seatID: hero, action: .raised(to: 40, amount: 40, isAllIn: false))
        XCTAssertEqual(TableAnnouncer.spoken(for: payload, heroSeatID: hero),
                       .heroActed(.raised(to: 40, amount: 40, isAllIn: false)))
    }

    func testHeroWinningThePotIsSpoken() {
        let payload = EventPayload.potAwarded(potIndex: 0, amount: 120, winnerSeatIDs: [2, hero])
        XCTAssertEqual(TableAnnouncer.spoken(for: payload, heroSeatID: hero), .heroWonPot(amount: 120))
    }

    // MARK: - Opponent / institutional moments → silent for VoiceOver

    func testOpponentActionsAreSilent() {
        XCTAssertNil(TableAnnouncer.spoken(for: .playerActed(seatID: 1, action: .folded), heroSeatID: hero))
        XCTAssertNil(TableAnnouncer.spoken(for: .playerActed(seatID: 2, action: .raised(to: 60, amount: 60, isAllIn: false)), heroSeatID: hero))
        XCTAssertNil(TableAnnouncer.spoken(for: .playerActed(seatID: 1, action: .checked), heroSeatID: hero))
    }

    func testBlindsStreetsShowdownAndHandStartAreSilent() {
        let handBegan = EventPayload.handBegan(handNumber: 0, buttonPosition: 0, buttonSeatID: 2,
                                               smallBlindSeatID: 0, bigBlindSeatID: 1,
                                               smallBlind: 10, bigBlind: 20, seats: [])
        XCTAssertNil(TableAnnouncer.spoken(for: handBegan, heroSeatID: hero))
        XCTAssertNil(TableAnnouncer.spoken(for: .blindPosted(seatID: hero, blind: .small, amount: 10, isAllIn: false), heroSeatID: hero))
        let flop = [Card(.ace, .spades), Card(.king, .hearts), Card(.two, .clubs)]
        XCTAssertNil(TableAnnouncer.spoken(for: .streetOpened(street: .flop, communityCards: flop), heroSeatID: hero))
        XCTAssertNil(TableAnnouncer.spoken(for: .handShown(seatID: 2, holeCards: flop, category: .pair, bestFive: flop), heroSeatID: hero))
    }

    func testPotAwardedToOthersIsSilent() {
        XCTAssertNil(TableAnnouncer.spoken(for: .potAwarded(potIndex: 0, amount: 100, winnerSeatIDs: [1, 2]), heroSeatID: hero))
    }

    func testDealtBustAndSessionEndAreSilent() {
        XCTAssertNil(TableAnnouncer.spoken(for: .playerBusted(playerID: 1), heroSeatID: hero))
        XCTAssertNil(TableAnnouncer.spoken(for: .holeCardsDealt(seatID: hero), heroSeatID: hero))
        XCTAssertNil(TableAnnouncer.spoken(for: .sessionEnded(reason: .stopped), heroSeatID: hero))
    }

    /// A private-hole-cards event for another seat (should the display ever see
    /// one) is not the human's business, so it stays silent.
    func testOtherSeatPrivateCardsAreSilent() {
        XCTAssertNil(TableAnnouncer.spoken(for: .privateHoleCards(seatID: 1, cards: [Card(.ace, .spades)]), heroSeatID: hero))
    }

    // MARK: - Card symbol formatting (pure, localization-free)

    func testCardSymbols() {
        XCTAssertEqual(CardText.symbol(Card(.ace, .spades)), "A♠")
        XCTAssertEqual(CardText.symbol(Card(.ten, .hearts)), "10♥")
        XCTAssertEqual(CardText.symbols([Card(.two, .clubs), Card(.king, .diamonds)]), "2♣ K♦")
    }
}
