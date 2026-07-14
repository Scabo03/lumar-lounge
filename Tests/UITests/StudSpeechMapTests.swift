import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine
import Audio

/// The Stud speech map (D-077/D-078): the authoritative event → speech-source plan, and
/// the permanent principle that it DESCRIBES the public state, never ADVISES a move.
final class StudSpeechMapTests: XCTestCase {

    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }
    private let names = [0: "Tu", 1: "lo Studente", 2: "il Professore"]

    // MARK: - Authoritative plan

    func testUpCardDealtIsAnnouncedToEveryone() {
        // Every up card is announced as it is dealt — parity with the sighted player who
        // SEES it appear (D-078). The hero's own up card uses the "you" phrasing.
        let opp = StudSpeechMap.plan(for: .upCardDealt(seatID: 2, card: c(.king, .hearts), street: .fourth),
                                     heroSeatID: 0, names: names)
        guard case let .upCard(who, card, isHero)? = opp.synthesis else { return XCTFail("expected an up-card line") }
        XCTAssertEqual(who, "il Professore"); XCTAssertEqual(card, c(.king, .hearts)); XCTAssertFalse(isHero)

        let hero = StudSpeechMap.plan(for: .upCardDealt(seatID: 0, card: c(.nine, .spades), street: .fourth),
                                      heroSeatID: 0, names: names)
        guard case let .upCard(_, _, heroFlag)? = hero.synthesis else { return XCTFail("expected an up-card line") }
        XCTAssertTrue(heroFlag)
    }

    func testHeroDownCardsAreHeroOnly() {
        let hero = StudSpeechMap.plan(for: .privateDownCards(seatID: 0, cards: [c(.ace, .spades)]),
                                      heroSeatID: 0, names: names)
        if case .heroDownCards? = hero.synthesis {} else { XCTFail("the hero hears their own down cards") }
        // A different seat's private cards are not the hero's business → silent for them.
        let other = StudSpeechMap.plan(for: .privateDownCards(seatID: 1, cards: [c(.ace, .spades)]),
                                       heroSeatID: 0, names: names)
        XCTAssertEqual(other, .silent)
    }

    /// The House Prize is NOT an event plan (D-079): it is paid at cash-out and narrated by
    /// the view model at the win — the map produces no prize plan. Its synth LINE still
    /// renders (used by that win narration).
    func testHousePrizeIsNarratedByLineNotByEventPlan() {
        // The prize line renders with its amount.
        XCTAssertFalse(StudSpeechMap.text(for: .housePrize(amount: 1500)).isEmpty)
        XCTAssertEqual(StudSpeechMap.priority(for: .housePrize(amount: 1500)), .high)
    }

    /// The all-in croupier cue was not delivered → its register is SILENT (lower verbosity,
    /// D-080), but the opponent action CONTENT still speaks (accessibility preserved).
    func testAllInHasNoCroupierCueButKeepsTheActionContent() {
        let plan = StudSpeechMap.plan(for: .playerActed(seatID: 2, action: .raised(to: 400, amount: 400, isAllIn: true)),
                                      heroSeatID: 0, names: names)
        XCTAssertNil(plan.croupier, "no all-in register cue (silenced, D-080)")
        if case .opponentAction? = plan.synthesis {} else { XCTFail("the all-in action content still speaks") }
    }

    /// A split pot uses the delivered split-pot cue; a single-winner pot the pot cue (D-080).
    func testPotUsesTheDeliveredCue() {
        let single = StudSpeechMap.plan(for: .potAwarded(potIndex: 0, amount: 300, winnerSeatIDs: [2]),
                                        heroSeatID: 0, names: names)
        XCTAssertEqual(single.croupier, SoundCatalog.voTowerPotAwarded)
        let split = StudSpeechMap.plan(for: .potAwarded(potIndex: 0, amount: 300, winnerSeatIDs: [1, 2]),
                                       heroSeatID: 0, names: names)
        XCTAssertEqual(split.croupier, SoundCatalog.voTowerSplitPot)
    }

    /// The Stud street change is silent (the delivered set has no Stud street cues); the up
    /// cards still carry the progression (D-080).
    func testStreetChangeIsSilent() {
        XCTAssertEqual(StudSpeechMap.plan(for: .streetBegan(street: .fifth), heroSeatID: 0, names: names), .silent)
    }

    /// No event is ever spoken by BOTH a synthesis line AND a croupier fallback with the
    /// same text (the D-051 anti-pattern) — the croupier's register fallback and the
    /// content synthesis are always different things.
    func testNoEventDeclaresSynthesisAndFallbackTogether() {
        let events: [StudEventPayload] = [
            .handBegan(handNumber: 0, ante: 25, bringIn: 25, bet: 50, seats: []),
            .upCardDealt(seatID: 1, card: c(.king, .hearts), street: .fourth),
            .streetBegan(street: .fifth),
            .playerActed(seatID: 1, action: .raised(to: 100, amount: 100, isAllIn: false)),
            .handShown(seatID: 1, cards: [], category: .pair, bestFive: []),
            .potAwarded(potIndex: 0, amount: 300, winnerSeatIDs: [1]),
        ]
        for e in events {
            let plan = StudSpeechMap.plan(for: e, heroSeatID: 0, names: names)
            XCTAssertFalse(plan.synthesis != nil && plan.croupierFallback != nil,
                           "\(e): never both a synthesis and a croupier fallback (D-051)")
        }
    }

    // MARK: - DESCRIBES, never ADVISES (D-078, CONVENTIONS)

    /// The Italian strings that describe opponents' boards and actions must contain NO
    /// advisory language — the system states the public facts, it never coaches a move.
    func testStudAnnouncementsDescribeAndNeverAdvise() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Resources/it.lproj/Localizable.strings")
        let strings = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])

        // Advisory words that would mean the game is playing FOR the player.
        let forbidden = ["puoi ", "potresti", "dovresti", "attento", "attenzione", "conviene",
                         "meglio", "rischi", "consiglio", "suggeri", "dovrebbe"]
        let describeKeys = strings.keys.filter {
            $0.hasPrefix("stud.announce.") || $0.hasPrefix("stud.seat.") || $0 == "stud.hero.cards.a11y"
        }
        XCTAssertGreaterThan(describeKeys.count, 10, "the Stud descriptive keys are present")
        for key in describeKeys {
            let value = strings[key]!.lowercased()
            for word in forbidden {
                XCTAssertFalse(value.contains(word), "\(key) must describe, not advise — found “\(word)” in “\(value)”")
            }
        }
        // The interrogation label really carries the board (a card placeholder), i.e. it
        // reads the opponent's exposed cards rather than a summary/hint.
        XCTAssertTrue((strings["stud.seat.upcards.a11y"] ?? "").contains("%@"),
                      "the opponent interrogation reads the actual exposed cards")
    }
}
