import XCTest
@testable import UI
import GameWorld
import GameEngine
import Audio

/// Characterises the authoritative event → speech-source mapping (D-029): who
/// speaks each moment, croupier mp3 and/or VoiceOver synthesis, or neither.
final class SpeechMapTests: XCTestCase {

    private let hero = 0
    private let names = [0: "Tu", 1: "Novice", 2: "Rock", 3: "Aggressor"]

    private func plan(_ payload: EventPayload) -> SpeechPlan {
        SpeechMap.plan(for: payload, heroSeatID: hero, names: names)
    }

    // MARK: - Croupier-only institutional moments

    func testHandStartAndBlinds() {
        XCTAssertEqual(plan(.handBegan(handNumber: 0, buttonPosition: 0, buttonSeatID: 2,
                                       smallBlindSeatID: 0, bigBlindSeatID: 1,
                                       smallBlind: 10, bigBlind: 20, seats: [])),
                       SpeechPlan(croupier: SoundCatalog.voHandStart))
        XCTAssertEqual(plan(.blindPosted(seatID: 0, blind: .small, amount: 10, isAllIn: false)),
                       SpeechPlan(croupier: SoundCatalog.voBlindSmall))
        XCTAssertEqual(plan(.blindPosted(seatID: 1, blind: .big, amount: 20, isAllIn: false)),
                       SpeechPlan(croupier: SoundCatalog.voBlindBig))
    }

    // MARK: - Croupier + synthesis (mp3 first, then content it can't pre-record)

    func testStreetsPlayCroupierThenReadTheCards() {
        let flop = [Card(.ace, .spades), Card(.king, .hearts), Card(.two, .clubs)]
        XCTAssertEqual(plan(.streetOpened(street: .flop, communityCards: flop)),
                       SpeechPlan(croupier: SoundCatalog.voFlop, synthesis: .communityCards(flop)))
        let turn = [Card(.ten, .diamonds)]
        XCTAssertEqual(plan(.streetOpened(street: .turn, communityCards: turn)),
                       SpeechPlan(croupier: SoundCatalog.voTurn, synthesis: .communityCards(turn)))
        let river = [Card(.five, .clubs)]
        XCTAssertEqual(plan(.streetOpened(street: .river, communityCards: river)),
                       SpeechPlan(croupier: SoundCatalog.voRiver, synthesis: .communityCards(river)))
    }

    func testShowdownPlaysCroupierThenReadsTheHand() {
        let hole = [Card(.ace, .spades), Card(.ace, .diamonds)]
        XCTAssertEqual(plan(.handShown(seatID: 2, holeCards: hole, category: .pair, bestFive: hole)),
                       SpeechPlan(croupier: SoundCatalog.voShowdown,
                                  synthesis: .shown(who: "Rock", cards: hole, category: .pair)))
    }

    // MARK: - Synthesis-only (personal to the human)

    func testHeroHoleCardsAreSynthesisOnly() {
        let cards = [Card(.ace, .spades), Card(.king, .hearts)]
        XCTAssertEqual(plan(.privateHoleCards(seatID: hero, cards: cards)),
                       SpeechPlan(synthesis: .heroCards(cards)))
    }

    func testOtherSeatPrivateCardsAreSilent() {
        XCTAssertEqual(plan(.privateHoleCards(seatID: 1, cards: [Card(.two, .clubs)])), .silent)
    }

    // MARK: - All-in

    func testAllInActionCallsTheCroupier() {
        XCTAssertEqual(plan(.playerActed(seatID: 1, action: .raised(to: 300, amount: 300, isAllIn: true))),
                       SpeechPlan(croupier: SoundCatalog.voActionAllIn))
        XCTAssertEqual(plan(.playerActed(seatID: 0, action: .called(amount: 300, isAllIn: true))),
                       SpeechPlan(croupier: SoundCatalog.voActionAllIn))
    }

    // MARK: - Silent for the spoken layer

    func testNonAllInActionsAreSilent() {
        XCTAssertEqual(plan(.playerActed(seatID: 1, action: .folded)), .silent)
        XCTAssertEqual(plan(.playerActed(seatID: 1, action: .checked)), .silent)
        XCTAssertEqual(plan(.playerActed(seatID: 1, action: .raised(to: 60, amount: 60, isAllIn: false))), .silent)
        XCTAssertEqual(plan(.playerActed(seatID: hero, action: .raised(to: 60, amount: 60, isAllIn: false))), .silent)
    }

    func testHoleDealtBustJoinsAndSessionAreSilent() {
        XCTAssertEqual(plan(.holeCardsDealt(seatID: 0)), .silent)
        XCTAssertEqual(plan(.playerBusted(playerID: 1)), .silent)
        XCTAssertEqual(plan(.sessionBegan(seats: [], smallBlind: 10, bigBlind: 20)), .silent)
        XCTAssertEqual(plan(.sessionEnded(reason: .stopped)), .silent)
    }

    // MARK: - Pot

    func testPotAwardedPlaysPotVoiceAndNamesWinner() {
        // Hero among winners → heroWon (category filled later by the consumer).
        XCTAssertEqual(plan(.potAwarded(potIndex: 0, amount: 100, winnerSeatIDs: [hero])),
                       SpeechPlan(croupier: SoundCatalog.voPotAwarded, synthesis: .heroWon(category: nil)))
        // Others win → otherWon with the resolved name.
        XCTAssertEqual(plan(.potAwarded(potIndex: 0, amount: 100, winnerSeatIDs: [1])),
                       SpeechPlan(croupier: SoundCatalog.voPotAwarded, synthesis: .otherWon(who: "Novice", category: nil)))
        // A split uses the split-pot voice.
        XCTAssertEqual(plan(.potAwarded(potIndex: 0, amount: 100, winnerSeatIDs: [1, 2])).croupier,
                       SoundCatalog.voSplitPot)
    }

    // MARK: - Card symbol formatting (pure)

    func testCardSymbols() {
        XCTAssertEqual(CardText.symbol(Card(.ace, .spades)), "A♠")
        XCTAssertEqual(CardText.symbols([Card(.two, .clubs), Card(.king, .diamonds)]), "2♣ K♦")
    }
}
