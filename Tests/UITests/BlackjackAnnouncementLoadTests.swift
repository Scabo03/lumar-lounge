// BlackjackAnnouncementLoadTests.swift
// =====================================================================
// THE MEASUREMENT (D-091).
//
// Blackjack's whole accessibility problem is speed. A round is two cards
// and a decision; a sighted player gets through dozens of them in minutes.
// If the blind player had to sit through a poker-sized load of announcements
// each round, they would be playing a slow version of the fast game — and
// "nobody loses anything" would be broken in the one place it is easiest to
// break it.
//
// So the requirement is not "it feels brisk" but a NUMBER, measured against
// the poker table that already exists, and held there by a test. CONVENTIONS
// §4 (D-075) is explicit that duration is measured in real navigation work,
// not in events; here the proxy is SPOKEN SECONDS PER ROUND, using the same
// estimator the announcement queue itself uses to budget the channel.

import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine

final class BlackjackAnnouncementLoadTests: XCTestCase {

    // MARK: - Measuring

    private struct Load {
        var rounds: Int
        var lines: Int
        var seconds: TimeInterval
        var linesPerRound: Double { Double(lines) / Double(max(rounds, 1)) }
        var secondsPerRound: TimeInterval { seconds / Double(max(rounds, 1)) }
    }

    /// Plays real blackjack rounds and totals what the player would actually hear.
    @MainActor
    private func measureBlackjack(rounds: Int, seed: UInt64) async throws -> Load {
        let provider = ScriptedBlackjackActionProvider(bet: 20) { context in
            // An ordinary, sensible player: draw while low, otherwise stop.
            context.total < 17 ? .hit : .stand
        }
        let driver = BlackjackSessionDriver(chips: 200_000, rules: .riverwood,
                                            provider: provider, seed: seed)

        var lines = 0
        var seconds: TimeInterval = 0
        let italian = BlackjackLocalizedStrings.localizer()
        let stream = await driver.events()
        let collector = Task { @MainActor in
            for await event in stream {
                let plan = BlackjackSpeechMap.plan(for: event.payload)
                if let line = plan.synthesis {
                    lines += 1
                    let text = BlackjackSpeechMap.text(for: line, localized: italian)
                    seconds += AnnouncementQueue.speakTime(text)
                }
            }
        }
        let played = try await driver.run(maxRounds: rounds)
        await driver.endSession()
        _ = await collector.value

        return Load(rounds: played.count, lines: lines, seconds: seconds)
    }

    /// The same measurement on the Seven-Card Stud table, as the reference point.
    @MainActor
    private func measureStud(hands: Int, seed: UInt64) async throws -> Load {
        let rules = StudTableRules.clockTower
        let bots = rules.personalities.enumerated().map { index, personality in
            StudSeatAssignment(position: index, playerID: index, chips: 3000,
                               provider: StudBotActionProvider(
                                HeuristicStudBot(personality: personality,
                                                 seed: UInt64(index) &+ seed)))
        }
        let third = StudSeatAssignment(position: 2, playerID: 2, chips: 3000,
                                       provider: StudBotActionProvider(
                                        HeuristicStudBot(personality: rules.personalities[0],
                                                         seed: seed &+ 99)))
        let driver = StudSessionDriver(capacity: 3, seats: bots + [third],
                                       ante: rules.ante, bringIn: rules.bringIn, bet: rules.bet,
                                       seed: seed)

        var lines = 0
        var seconds: TimeInterval = 0
        let names = [0: "uno", 1: "due", 2: "tre"]
        let stream = await driver.events(as: EventViewer.player(0))
        let collector = Task { @MainActor in
            for await event in stream {
                // Counted in LINES only: StudSpeechMap renders through the app
                // bundle, which is absent here, so its text length would be a
                // measure of key names. Lines per hand needs no localization to
                // be an honest comparison.
                if StudSpeechMap.plan(for: event.payload, heroSeatID: 0, names: names).synthesis != nil {
                    lines += 1
                }
            }
        }
        let played = try await driver.run(maxHands: hands)
        await driver.endSession()
        _ = await collector.value

        return Load(rounds: played.count, lines: lines, seconds: seconds)
    }

    // MARK: - The requirement

    @MainActor
    func testABlackjackRoundIsDRAMATICALLYlighterThanAPokerHand() async throws {
        let blackjack = try await measureBlackjack(rounds: 60, seed: 4242)
        let stud = try await measureStud(hands: 40, seed: 4242)

        print("""

        ── SPOKEN LOAD, MEASURED ──────────────────────────────
          Blackjack  \(blackjack.rounds) rounds  \
        \(String(format: "%.2f", blackjack.linesPerRound)) lines/round  \
        \(String(format: "%.2f", blackjack.secondsPerRound)) s/round
          Stud       \(stud.rounds) hands   \
        \(String(format: "%.2f", stud.linesPerRound)) lines/hand
        ───────────────────────────────────────────────────────

        """)

        XCTAssertGreaterThan(blackjack.rounds, 40, "The measurement needs real rounds behind it.")

        // The cross-game bar is in LINES, the one unit that needs no bundle to
        // be honest. Measured: roughly 3.9 against roughly 20 — a blackjack
        // round asks about a fifth of what a Stud hand asks of the ear.
        XCTAssertLessThan(blackjack.linesPerRound, stud.linesPerRound * 0.30,
                          "A blackjack round must cost a small fraction of a Stud hand.")

        // And an absolute ceiling, so the guard survives a future change to the
        // Stud table: a round the player can get through in a breath.
        // An absolute ceiling too, so the guard survives a future change to the
        // Stud table. Measured at roughly four and a half spoken seconds across
        // four short lines; five is the bar, with headroom but no room to drift
        // back into reading cards out.
        XCTAssertLessThan(blackjack.secondsPerRound, 7.0,
                          "A blackjack round must stay under seven spoken seconds.")
        XCTAssertLessThan(blackjack.linesPerRound, 4.5,
                          "A blackjack round must stay under four and a half spoken lines.")
    }

    // MARK: - Where the compactness comes from

    @MainActor
    func testTheDealLineCarriesTheDEALERSCardAndNotThePlayersOwnTotal() throws {
        // REVISED in D-096. D-091 packed the total and the dealer's card into one
        // line, and on a real device that was worse than either half: the hand
        // element appeared at the same instant, VoiceOver focus landed on it and
        // began reading the total, and this line fired on top of it. The two
        // talked over each other and the dealer's card — the half the element does
        // NOT carry — was the one that got lost.
        //
        // So the line now says only what no element is about to say by itself,
        // and it is spoken a beat later, into a quiet channel.
        let plan = BlackjackSpeechMap.plan(for: .dealt(playerCards: [Card(.ace, .spades),
                                                                    Card(.six, .hearts)],
                                                       total: 17, isSoft: true,
                                                       dealerUpCard: Card(.ten, .clubs),
                                                       isNatural: false))
        let line = try XCTUnwrap(plan.synthesis)
        let text = BlackjackSpeechMap.text(for: line,
                                           localized: BlackjackLocalizedStrings.localizer())

        XCTAssertTrue(text.lowercased().contains("dieci"),
                      "The dealer's up card is what this line exists to carry: \(text)")
        XCTAssertFalse(text.contains("17"),
                       "The player's total belongs to the hand element, which focus lands on: \(text)")
        XCTAssertFalse(text.lowercased().contains("asso"),
                       "The player's own cards are NOT read out on every deal: \(text)")
        XCTAssertFalse(text.lowercased().contains("fiori"),
                       "The SUIT cannot affect anything in blackjack, so it is not spoken: \(text)")
        XCTAssertLessThan(AnnouncementQueue.speakTime(text), 2.0,
                          "Short enough to be worth hearing every round.")
    }

    @MainActor
    func testANaturalStillGetsItsOwnLine() throws {
        // The exception: a natural settles the hand at once, so it is worth
        // saying rather than leaving to be discovered on an element.
        let plan = BlackjackSpeechMap.plan(for: .dealt(playerCards: [Card(.ace, .spades),
                                                                    Card(.king, .hearts)],
                                                       total: 21, isSoft: true,
                                                       dealerUpCard: Card(.ten, .clubs),
                                                       isNatural: true))
        let text = BlackjackSpeechMap.text(for: try XCTUnwrap(plan.synthesis),
                                           localized: BlackjackLocalizedStrings.localizer())
        XCTAssertTrue(text.lowercased().contains("blackjack"), "A natural announces itself: \(text)")
    }

    /// The dealer's total is the REASON a hand ended as it did, so it must never
    /// be the line the channel gives up (D-096). It was `.medium`, droppable
    /// alongside chatter — in a game that has no chatter.
    func testTheDealersTotalIsNeverDroppable() {
        let dealer = BlackjackSpeechMap.priority(for: .dealer(cards: [Card(.ten, .clubs),
                                                                      Card(.nine, .hearts)],
                                                              total: 19, isSoft: false,
                                                              didBust: false, hasNatural: false))
        XCTAssertEqual(dealer, .high, "The cause of the result is as protected as the result.")
    }

    func testASingleHandIsNotToldWhoseTurnItIs() {
        // With one hand this repeats what the deal line just said, and the
        // player knows it by the structure of the game (D-089).
        let single = BlackjackSpeechMap.plan(for: .handTurnBegan(handIndex: 0,
                                                                 cards: [Card(.ten, .spades)],
                                                                 total: 10, isSoft: false,
                                                                 handCount: 1))
        XCTAssertEqual(single, .silent)

        // After a split it earns its place: several hands really do need telling apart.
        let split = BlackjackSpeechMap.plan(for: .handTurnBegan(handIndex: 1,
                                                                cards: [Card(.ten, .spades)],
                                                                total: 10, isSoft: false,
                                                                handCount: 2))
        XCTAssertNotEqual(split, .silent)
    }

    func testTheWagerAndTheStandAreNotSaidBackToThePlayer() {
        // The player pressed the button; it already spoke (D-055).
        XCTAssertEqual(BlackjackSpeechMap.plan(for: .roundBegan(roundNumber: 1, bet: 20, chips: 980)),
                       .silent)
        XCTAssertEqual(BlackjackSpeechMap.plan(for: .playerActed(handIndex: 0,
                                                                 action: .stood(total: 19),
                                                                 chips: 980)),
                       .silent)
    }

    func testASingleHandRoundGetsNoRedundantSummary() {
        // One hand: the settlement line already gave the figure.
        XCTAssertEqual(BlackjackSpeechMap.plan(for: .roundEnded(roundNumber: 1, net: 20,
                                                                chips: 1020, handCount: 1)),
                       .silent)
        // Several hands genuinely need adding up.
        XCTAssertNotEqual(BlackjackSpeechMap.plan(for: .roundEnded(roundNumber: 1, net: 20,
                                                                   chips: 1020, handCount: 2)),
                          .silent)
    }

    // MARK: - The detail is available, just not imposed

    func testTheCardsBehindTheTotalAreReachableOnDemand() {
        let hand = BlackjackHandPresentation(cards: [Card(.ace, .spades), Card(.six, .hearts)],
                                             bet: 20)
        let readout = BlackjackReadout.hand(hand, index: 0, handCount: 1) { key, args in
            "\(key)|\(args.map { "\($0)" }.joined(separator: ","))"
        }
        XCTAssertTrue(readout.contains("blackjack.hero.hand.a11y"),
                      "The interrogable element exists and carries the cards.")

        // And the ORDER is total first, cards after (D-083): what is wanted most
        // often must not sit behind a preamble.
        let real = BlackjackReadout.hand(hand, index: 0, handCount: 1,
                                         localized: BlackjackLocalizedStrings.localizer())
        let totalAt = real.range(of: "17")
        let cardsAt = real.lowercased().range(of: "asso")
        XCTAssertNotNil(totalAt, "The total is in the readout: \(real)")
        XCTAssertNotNil(cardsAt, "And so are the cards behind it: \(real)")
        if let t = totalAt, let c = cardsAt {
            XCTAssertLessThan(t.lowerBound, c.lowerBound, "The total leads; the cards follow.")
        }
    }

    func testTheDealerIsReadableOnDemandBothBeforeAndAfterTheHoleCard() {
        let italian = BlackjackLocalizedStrings.localizer()
        let hidden = BlackjackReadout.dealer(cards: [Card(.ten, .clubs)],
                                             holeCardHidden: true, localized: italian)
        XCTAssertTrue(hidden.lowercased().contains("dieci"),
                      "The up card is readable on demand: \(hidden)")

        let shown = BlackjackReadout.dealer(cards: [Card(.ten, .clubs), Card(.eight, .hearts)],
                                            holeCardHidden: false, localized: italian)
        XCTAssertTrue(shown.contains("18"),
                      "Once the hole card is up the total is the headline: \(shown)")
        XCTAssertTrue(shown.lowercased().contains("otto"),
                      "And the cards that built it are there for the asking: \(shown)")
    }
}
