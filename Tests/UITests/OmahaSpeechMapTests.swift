import XCTest
@testable import UI
import GameWorld
import GameEngine
import Audio

/// The Omaha event → speech mapping (D-066): the authoritative plan (who speaks each
/// moment), and the four-hole-card announcement GROUPED BY SUIT so a blind player
/// hears suitedness without drowning. Plan tests are pure (no localization); the
/// grouping test asserts structure, which survives the key-only lookup under `swift test`.
final class OmahaSpeechMapTests: XCTestCase {

    private let names = [0: "Tu", 1: "Bot 1", 2: "Bot 2"]
    private let c = { (r: Rank, s: Suit) in Card(r, s) }

    func testHandBeganUsesTheSkypoolCroupier() {
        let plan = OmahaSpeechMap.plan(for: .handBegan(handNumber: 0, buttonPosition: 0, buttonSeatID: 0,
                                                       smallBlindSeatID: 1, bigBlindSeatID: 2, smallBlind: 25,
                                                       bigBlind: 50, seats: []), heroSeatID: 0, names: names)
        XCTAssertEqual(plan.croupier, SoundCatalog.voSkyHandStart)   // distinct Skypool voice
    }

    func testHeroHoleCardsAreSynthesizedOwnCardsOnly() {
        let hero = [c(.ace, .spades), c(.king, .spades), c(.ten, .hearts), c(.five, .clubs)]
        let mine = OmahaSpeechMap.plan(for: .privateHoleCards(seatID: 0, cards: hero), heroSeatID: 0, names: names)
        XCTAssertEqual(mine.synthesis, .heroCards(hero))
        // Another seat's private cards are never in the hero's plan.
        let theirs = OmahaSpeechMap.plan(for: .privateHoleCards(seatID: 1, cards: hero), heroSeatID: 0, names: names)
        XCTAssertEqual(theirs, .silent)
    }

    func testStreetOpenedSaysStreetThenCardsWithFallback() {
        let flop = [c(.two, .diamonds), c(.seven, .clubs), c(.queen, .hearts)]
        let plan = OmahaSpeechMap.plan(for: .streetOpened(street: .flop, communityCards: flop), heroSeatID: 0, names: names)
        XCTAssertEqual(plan.croupier, SoundCatalog.voSkyFlop)
        XCTAssertEqual(plan.synthesis, .communityCards(flop))       // the concrete cards
        XCTAssertEqual(plan.croupierFallback, .streetName(.flop))   // the word, until the mp3 exists
    }

    func testOpponentActionAttributedHeroActionSilent() {
        let opp = OmahaSpeechMap.plan(for: .playerActed(seatID: 1, action: .raised(to: 150, amount: 150, isAllIn: false)),
                                      heroSeatID: 0, names: names)
        XCTAssertEqual(opp.synthesis, .opponentAction(seat: 1, action: .raised(to: 150, amount: 150, isAllIn: false)))
        let hero = OmahaSpeechMap.plan(for: .playerActed(seatID: 0, action: .called(amount: 50, isAllIn: false)),
                                       heroSeatID: 0, names: names)
        XCTAssertEqual(hero, .silent)   // physical sounds only for the human's own action
    }

    func testPotAndShowdownUseOncePerHandCroupierVoices() {
        let pot = OmahaSpeechMap.plan(for: .potAwarded(potIndex: 0, amount: 300, winnerSeatIDs: [0]),
                                      heroSeatID: 0, names: names)
        XCTAssertEqual(pot.croupier, SoundCatalog.voSkyPotAwarded)
        XCTAssertEqual(pot.synthesis, .heroWon(category: nil, bestFive: nil))
        // These Skypool voices are in the conductor's once-per-hand list (D-051).
        XCTAssertTrue(SpeechConductor.oncePerHandVoices.isSuperset(of: [
            SoundCatalog.voSkyShowdown, SoundCatalog.voSkyPotAwarded, SoundCatalog.voSkySplitPot]))
    }

    func testRoleAnnouncementIsPersonalWithFallback() {
        let began = OmahaEventPayload.handBegan(handNumber: 0, buttonPosition: 0, buttonSeatID: 2,
                                                smallBlindSeatID: 0, bigBlindSeatID: 1, smallBlind: 25,
                                                bigBlind: 50, seats: [])
        // Hero is the small blind → its own role, with a synthesis fallback (D-030).
        let plan = OmahaSpeechMap.roleAnnouncement(for: began, heroSeatID: 0)
        XCTAssertEqual(plan.croupier, SoundCatalog.voSkyBlindSmall)
        XCTAssertEqual(plan.croupierFallback, .roleSmallBlind)
        // A seat with no role → silence.
        XCTAssertEqual(OmahaSpeechMap.roleAnnouncement(for: began, heroSeatID: 9), .silent)
    }

    // MARK: - Four hole cards grouped BY SUIT (D-066)

    func testHoleCardsAreGroupedBySuit() {
        // AsKs Th 5c → three suits {spades×2, hearts×1, clubs×1} → THREE groups.
        let hand = [c(.ace, .spades), c(.king, .spades), c(.ten, .hearts), c(.five, .clubs)]
        let spoken = OmahaSpeechMap.omahaHoleSpoken(hand)
        // Each suit-group renders through `card.spoken.format`; count the groups.
        XCTAssertEqual(groupCount(spoken), 3)

        // A double-suited hand AsKs 9h 8h → two suits → TWO groups.
        let doubleSuited = [c(.ace, .spades), c(.king, .spades), c(.nine, .hearts), c(.eight, .hearts)]
        XCTAssertEqual(groupCount(OmahaSpeechMap.omahaHoleSpoken(doubleSuited)), 2)

        // A rainbow-ish hand across four suits → FOUR groups.
        let rainbow = [c(.ace, .spades), c(.king, .hearts), c(.ten, .diamonds), c(.five, .clubs)]
        XCTAssertEqual(groupCount(OmahaSpeechMap.omahaHoleSpoken(rainbow)), 4)
    }

    /// Groups are joined by ", "; under `swift test` each group renders to the format
    /// key, so the group count = comma-separated segments.
    private func groupCount(_ spoken: String) -> Int {
        spoken.components(separatedBy: ", ").count
    }
}
