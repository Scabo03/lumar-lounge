import XCTest
@testable import UI
import GameWorld
import GameEngine
import Audio

/// Tests for the authoritative Five-Card Draw event → speech mapping (D-044): each
/// event has a single responsible source, croupier fallbacks are declared for the
/// not-yet-produced mp3s, and rendering never yields an empty string.
final class DrawSpeechMapTests: XCTestCase {

    private let names = [0: "Tu", 1: "Il Novizio", 2: "Il Sasso", 3: "L'Aggressivo"]
    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    func testAnteHasCroupierWithFallback() {
        let plan = DrawSpeechMap.plan(for: .handBegan(handNumber: 0, buttonPosition: 0, buttonSeatID: 0,
                                                      ante: 10, smallBet: 20, bigBet: 40, carriedPot: 0, seats: []),
                                      heroSeatID: 0, names: names)
        XCTAssertEqual(plan.croupier, SoundCatalog.voAnte)
        XCTAssertEqual(plan.croupierFallback, .ante)     // mp3 not produced yet (D-030)
    }

    func testHeroCardsAreSynthesisAndPrivate() {
        let mine = [c(.ace, .spades), c(.king, .spades), c(.two, .hearts), c(.seven, .clubs), c(.nine, .diamonds)]
        let heroPlan = DrawSpeechMap.plan(for: .privateCards(seatID: 0, cards: mine), heroSeatID: 0, names: names)
        XCTAssertEqual(heroPlan.synthesis, .heroCards(mine))
        // Another seat's private cards are not this hero's business → silent.
        let otherPlan = DrawSpeechMap.plan(for: .privateCards(seatID: 1, cards: mine), heroSeatID: 0, names: names)
        XCTAssertEqual(otherPlan, .silent)
    }

    func testOpponentActionAndDrawAreSynthesisedButHeroIsSilent() {
        let oppAct = DrawSpeechMap.plan(for: .playerActed(seatID: 2, action: .raised(amount: 40, isAllIn: false), round: .second),
                                        heroSeatID: 0, names: names)
        XCTAssertEqual(oppAct.synthesis, .opponentAction(seat: 2, action: .raised(amount: 40, isAllIn: false)))
        let heroAct = DrawSpeechMap.plan(for: .playerActed(seatID: 0, action: .raised(amount: 40, isAllIn: false), round: .second),
                                         heroSeatID: 0, names: names)
        XCTAssertEqual(heroAct, .silent)

        let oppDraw = DrawSpeechMap.plan(for: .playerDrew(seatID: 3, discardCount: 2), heroSeatID: 0, names: names)
        XCTAssertEqual(oppDraw.synthesis, .opponentDrew(seat: 3, count: 2))
        let heroDraw = DrawSpeechMap.plan(for: .playerDrew(seatID: 0, discardCount: 2), heroSeatID: 0, names: names)
        XCTAssertEqual(heroDraw, .silent)   // the hero drew it themselves; new cards are announced separately
    }

    func testPassAndOutAndDisqualificationHaveCroupierWithFallback() {
        let passed = DrawSpeechMap.plan(for: .passedIn(carriedPot: 40, consecutivePassed: 1), heroSeatID: 0, names: names)
        XCTAssertEqual(passed.croupier, SoundCatalog.voPassAndOut)
        XCTAssertEqual(passed.croupierFallback, .passedIn)

        let dq = DrawSpeechMap.plan(for: .openersDisqualified(seatID: 3), heroSeatID: 0, names: names)
        XCTAssertEqual(dq.croupier, SoundCatalog.voOpenersDisqualified)
        XCTAssertEqual(dq.synthesis, .openersDisqualified(seat: 3))
    }

    func testPotAwardedPicksSplitVsSingleAndHeroVsOther() {
        let heroWins = DrawSpeechMap.plan(for: .potAwarded(potIndex: 0, amount: 100, winnerSeatIDs: [0]),
                                          heroSeatID: 0, names: names)
        XCTAssertEqual(heroWins.croupier, SoundCatalog.voPotAwarded)
        XCTAssertEqual(heroWins.synthesis, .heroWon(category: nil))

        let split = DrawSpeechMap.plan(for: .potAwarded(potIndex: 0, amount: 100, winnerSeatIDs: [1, 2]),
                                       heroSeatID: 0, names: names)
        XCTAssertEqual(split.croupier, SoundCatalog.voSplitPot)
        if case .otherWon = split.synthesis {} else { XCTFail("expected otherWon") }
    }

    func testEverySynthLineRendersNonEmpty() {
        let lines: [DrawSynthLine] = [
            .ante, .carriedPot(80), .heroCards([c(.ace, .spades)]), .heroDrewCards([c(.two, .clubs)]),
            .opponentAction(seat: 1, action: .bet(amount: 20, isAllIn: false)),
            .opponentAction(seat: 1, action: .called(amount: 20, isAllIn: true)),
            .opponentDrew(seat: 2, count: 0), .opponentDrew(seat: 2, count: 3),
            .yourTurnContext(toCall: 20, pot: 100), .drawPhase, .passedIn,
            .shown(who: "Il Sasso", cards: [c(.ace, .spades)], category: .pair),
            .openersDisqualified(seat: 3), .heroWon(category: nil), .heroWon(category: .flush),
            .otherWon(who: "Tu", category: nil), .otherWon(who: "Tu", category: .straight),
            .sessionWon, .sessionLost,
        ]
        for line in lines {
            XCTAssertFalse(DrawSpeechMap.text(for: line).isEmpty, "empty render for \(line)")
        }
    }

    func testPrioritiesFollowStrategyC() {
        XCTAssertEqual(DrawSpeechMap.priority(for: .heroCards([])), .high)
        XCTAssertEqual(DrawSpeechMap.priority(for: .openersDisqualified(seat: 1)), .high)
        XCTAssertEqual(DrawSpeechMap.priority(for: .passedIn), .high)
        XCTAssertEqual(DrawSpeechMap.priority(for: .opponentAction(seat: 1, action: .checked)), .medium)
        XCTAssertEqual(DrawSpeechMap.priority(for: .opponentDrew(seat: 1, count: 2)), .medium)
    }
}
