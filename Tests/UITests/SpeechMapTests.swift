import XCTest
@testable import UI
import GameWorld
import GameEngine
import Audio

/// Characterises the authoritative event → speech-source mapping (D-029/D-030/
/// D-031): who speaks each moment, croupier mp3 and/or VoiceOver synthesis (with
/// fallback), or neither.
final class SpeechMapTests: XCTestCase {

    private let hero = 0
    private let names = [0: "Tu", 1: "Novice", 2: "Rock", 3: "Aggressor"]

    private func plan(_ payload: EventPayload) -> SpeechPlan {
        SpeechMap.plan(for: payload, heroSeatID: hero, names: names)
    }
    private func handBegan(button: Int = 2, sb: Int = 0, bb: Int = 1) -> EventPayload {
        .handBegan(handNumber: 0, buttonPosition: 0, buttonSeatID: button,
                   smallBlindSeatID: sb, bigBlindSeatID: bb, smallBlind: 10, bigBlind: 20, seats: [])
    }

    // MARK: - Hand start (no more generic blinds — D-031)

    func testHandStartIsCroupierAndBlindsAreNoLongerSpokenGenerically() {
        XCTAssertEqual(plan(handBegan()), SpeechPlan(croupier: SoundCatalog.voHandStart))
        XCTAssertEqual(plan(.blindPosted(seatID: 0, blind: .small, amount: 10, isAllIn: false)), .silent)
        XCTAssertEqual(plan(.blindPosted(seatID: 1, blind: .big, amount: 20, isAllIn: false)), .silent)
    }

    // MARK: - Role announcement, personal to the human (D-031)

    func testRoleAnnouncementIsTheHumansOwnRoleOrSilence() {
        func role(button: Int, sb: Int, bb: Int) -> SpeechPlan {
            SpeechMap.roleAnnouncement(for: handBegan(button: button, sb: sb, bb: bb), heroSeatID: hero)
        }
        XCTAssertEqual(role(button: 2, sb: 0, bb: 1), SpeechPlan(croupier: SoundCatalog.voBlindSmall)) // hero=SB
        XCTAssertEqual(role(button: 2, sb: 1, bb: 0), SpeechPlan(croupier: SoundCatalog.voBlindBig))   // hero=BB
        // hero on the button → not-yet-produced mp3 with a synthesis fallback (D-030)
        XCTAssertEqual(role(button: 0, sb: 1, bb: 2),
                       SpeechPlan(croupier: SoundCatalog.voRoleButton, croupierFallback: .roleButton))
        // hero has no role → silence
        XCTAssertEqual(role(button: 1, sb: 2, bb: 3), .silent)
    }

    func testRoleButtonFallbackText() {
        XCTAssertEqual(SpeechMap.text(for: .roleButton), uiLocalized("announce.role.button"))
    }

    // MARK: - Streets and showdown (croupier then content)

    func testStreetsPlayCroupierThenReadTheCards() {
        let flop = [Card(.ace, .spades), Card(.king, .hearts), Card(.two, .clubs)]
        XCTAssertEqual(plan(.streetOpened(street: .flop, communityCards: flop)),
                       SpeechPlan(croupier: SoundCatalog.voFlop, synthesis: .communityCards(flop)))
        XCTAssertEqual(plan(.streetOpened(street: .turn, communityCards: [Card(.ten, .diamonds)])).croupier,
                       SoundCatalog.voTurn)
    }

    // MARK: - Opponent actions fill the acoustic gap (D-031)

    func testOpponentActionsAreSynthesizedWithSeatNumber() {
        XCTAssertEqual(plan(.playerActed(seatID: 1, action: .folded)),
                       SpeechPlan(synthesis: .opponentAction(seat: 1, action: .folded)))
        XCTAssertEqual(plan(.playerActed(seatID: 2, action: .checked)).synthesis,
                       .opponentAction(seat: 2, action: .checked))
        XCTAssertEqual(plan(.playerActed(seatID: 3, action: .raised(to: 60, amount: 40, isAllIn: false))).synthesis,
                       .opponentAction(seat: 3, action: .raised(to: 60, amount: 40, isAllIn: false)))
    }

    func testOpponentAllInPlaysCroupierThenAttribution() {
        XCTAssertEqual(plan(.playerActed(seatID: 2, action: .raised(to: 300, amount: 300, isAllIn: true))),
                       SpeechPlan(croupier: SoundCatalog.voActionAllIn,
                                  synthesis: .opponentAction(seat: 2, action: .raised(to: 300, amount: 300, isAllIn: true))))
    }

    func testHeroOwnActionsAreSilentExceptCroupierAllIn() {
        XCTAssertEqual(plan(.playerActed(seatID: hero, action: .raised(to: 60, amount: 60, isAllIn: false))), .silent)
        XCTAssertEqual(plan(.playerActed(seatID: hero, action: .called(amount: 300, isAllIn: true))),
                       SpeechPlan(croupier: SoundCatalog.voActionAllIn))   // no attribution for the human
    }

    func testOpponentActionText() {
        XCTAssertEqual(SpeechMap.text(for: .opponentAction(seat: 2, action: .folded)),
                       uiLocalized("announce.opp.fold", 2))
        XCTAssertEqual(SpeechMap.text(for: .opponentAction(seat: 3, action: .raised(to: 60, amount: 40, isAllIn: false))),
                       uiLocalized("announce.opp.raise", 3, 60))
        XCTAssertEqual(SpeechMap.text(for: .opponentAction(seat: 1, action: .called(amount: 500, isAllIn: true))),
                       uiLocalized("announce.opp.allin", 1))
    }

    // MARK: - Personal synthesis & silence

    func testHeroHoleCardsAreSynthesisOnly() {
        let cards = [Card(.ace, .spades), Card(.king, .hearts)]
        XCTAssertEqual(plan(.privateHoleCards(seatID: hero, cards: cards)), SpeechPlan(synthesis: .heroCards(cards)))
    }

    func testHoleDealtBustJoinsAndSessionAreSilent() {
        XCTAssertEqual(plan(.holeCardsDealt(seatID: 0)), .silent)
        XCTAssertEqual(plan(.playerBusted(playerID: 1)), .silent)
        XCTAssertEqual(plan(.sessionEnded(reason: .stopped)), .silent)
    }

    // MARK: - Pot

    func testPotAwardedPlaysPotVoiceAndNamesWinner() {
        XCTAssertEqual(plan(.potAwarded(potIndex: 0, amount: 100, winnerSeatIDs: [hero])),
                       SpeechPlan(croupier: SoundCatalog.voPotAwarded, synthesis: .heroWon(category: nil, bestFive: nil)))
        XCTAssertEqual(plan(.potAwarded(potIndex: 0, amount: 100, winnerSeatIDs: [1, 2])).croupier,
                       SoundCatalog.voSplitPot)
    }

    // MARK: - Showdown announcements: combination + relevant kicker, never card-by-card (D-045)

    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    func testShownReadsCombinationNotCardByCard() {
        // A pair of aces with a queen kicker: bestFive ordered combo-first.
        let bestFive = [c(.ace, .spades), c(.ace, .hearts), c(.queen, .diamonds), c(.seven, .clubs), c(.three, .spades)]
        let text = SpeechMap.text(for: .shown(who: "Giocatore 2", category: .pair, bestFive: bestFive))
        // Shown = "who: combination" — the mapping composes announce.shown with the
        // hand description, never the individual cards.
        XCTAssertEqual(text, uiLocalized("announce.shown", "Giocatore 2",
                                         SpeechMap.handDescription(category: .pair, bestFive: bestFive)))
    }

    // Localized rank helpers (mirror the mapping's own composition, so these tests
    // verify KEY/variant selection and ARG placement regardless of whether the
    // .strings bundle is loaded under `swift test`).
    private func sing(_ r: Rank) -> String { uiLocalized("card.rank.\(r.rawValue)") }
    private func plur(_ r: Rank) -> String { uiLocalized("card.rank.plural.\(r.rawValue)") }

    func testHandDescriptionPerCategory() {
        func desc(_ cat: HandCategory, _ cards: [Card]) -> String {
            SpeechMap.handDescription(category: cat, bestFive: cards)
        }
        // Pair of aces, queen kicker → combination + top kicker.
        XCTAssertEqual(desc(.pair, [c(.ace,.spades), c(.ace,.hearts), c(.queen,.diamonds), c(.seven,.clubs), c(.three,.spades)]),
                       uiLocalized("hand.desc.pair", plur(.ace), sing(.queen)))
        // Two pair, aces and tens, queen kicker.
        XCTAssertEqual(desc(.twoPair, [c(.ace,.spades), c(.ace,.hearts), c(.ten,.diamonds), c(.ten,.clubs), c(.queen,.spades)]),
                       uiLocalized("hand.desc.twopair", plur(.ace), plur(.ten), sing(.queen)))
        // Trips, kings, ace kicker.
        XCTAssertEqual(desc(.threeOfAKind, [c(.king,.spades), c(.king,.hearts), c(.king,.diamonds), c(.ace,.clubs), c(.three,.spades)]),
                       uiLocalized("hand.desc.trips", plur(.king), sing(.ace)))
        // Full house, kings over sevens (no kicker).
        XCTAssertEqual(desc(.fullHouse, [c(.king,.spades), c(.king,.hearts), c(.king,.diamonds), c(.seven,.clubs), c(.seven,.spades)]),
                       uiLocalized("hand.desc.fullhouse", plur(.king), plur(.seven)))
        // Four of a kind, aces.
        XCTAssertEqual(desc(.fourOfAKind, [c(.ace,.spades), c(.ace,.hearts), c(.ace,.diamonds), c(.ace,.clubs), c(.two,.spades)]),
                       uiLocalized("hand.desc.quads", plur(.ace)))
        // Royal flush: no rank, no kicker.
        XCTAssertEqual(desc(.royalFlush, [c(.ace,.spades), c(.king,.spades), c(.queen,.spades), c(.jack,.spades), c(.ten,.spades)]),
                       uiLocalized("hand.desc.royal"))
    }

    func testElisionVariantChosenByHighCard() {
        // Ace-high flush → the vowel elision variant ("colore all'asso").
        XCTAssertEqual(SpeechMap.handDescription(category: .flush,
                        bestFive: [c(.ace,.hearts), c(.jack,.hearts), c(.eight,.hearts), c(.five,.hearts), c(.two,.hearts)]),
                       uiLocalized("hand.desc.flush.vowel", sing(.ace)))
        // King-high flush → the plain variant ("colore al re").
        XCTAssertEqual(SpeechMap.handDescription(category: .flush,
                        bestFive: [c(.king,.hearts), c(.jack,.hearts), c(.eight,.hearts), c(.five,.hearts), c(.two,.hearts)]),
                       uiLocalized("hand.desc.flush", sing(.king)))
        // Straight flush to the king → plain variant.
        XCTAssertEqual(SpeechMap.handDescription(category: .straightFlush,
                        bestFive: [c(.king,.spades), c(.queen,.spades), c(.jack,.spades), c(.ten,.spades), c(.nine,.spades)]),
                       uiLocalized("hand.desc.straightflush", sing(.king)))
    }

    func testStraightWheelReadsFiveHighNotAceHigh() {
        // A-2-3-4-5: the evaluated cards sort the ace first, but the straight is
        // five-high → "scala al cinque", NOT the ace.
        let wheel = [c(.ace,.spades), c(.five,.hearts), c(.four,.diamonds), c(.three,.clubs), c(.two,.spades)]
        XCTAssertEqual(SpeechMap.handDescription(category: .straight, bestFive: wheel),
                       uiLocalized("hand.desc.straight", sing(.five)))
        // A broadway straight IS ace-high → the vowel variant.
        let broadway = [c(.ace,.spades), c(.king,.hearts), c(.queen,.diamonds), c(.jack,.clubs), c(.ten,.spades)]
        XCTAssertEqual(SpeechMap.handDescription(category: .straight, bestFive: broadway),
                       uiLocalized("hand.desc.straight.vowel", sing(.ace)))
    }

    func testHeroWonReadsCombinationWithKicker() {
        let bestFive = [c(.king,.spades), c(.king,.hearts), c(.king,.diamonds), c(.seven,.clubs), c(.seven,.spades)]
        XCTAssertEqual(SpeechMap.text(for: .heroWon(category: .fullHouse, bestFive: bestFive)),
                       uiLocalized("announce.hero.won.category", SpeechMap.handDescription(category: .fullHouse, bestFive: bestFive)))
        // Fold-out win (no showdown hand) falls back to the plain line.
        XCTAssertEqual(SpeechMap.text(for: .heroWon(category: nil, bestFive: nil)), uiLocalized("announce.hero.won"))
    }

    func testSplitWonNamesTheSharedCombination() {
        let bestFive = [c(.ace,.spades), c(.ace,.hearts), c(.queen,.diamonds), c(.seven,.clubs), c(.three,.spades)]
        XCTAssertEqual(SpeechMap.text(for: .splitWon(who: "Giocatore 2, Giocatore 3", category: .pair, bestFive: bestFive)),
                       uiLocalized("announce.split.won", "Giocatore 2, Giocatore 3",
                                   SpeechMap.handDescription(category: .pair, bestFive: bestFive)))
    }
}
