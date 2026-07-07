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
                       SpeechPlan(croupier: SoundCatalog.voPotAwarded, synthesis: .heroWon(category: nil)))
        XCTAssertEqual(plan(.potAwarded(potIndex: 0, amount: 100, winnerSeatIDs: [1, 2])).croupier,
                       SoundCatalog.voSplitPot)
    }
}
