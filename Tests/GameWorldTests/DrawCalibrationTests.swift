// DrawCalibrationTests.swift
// =====================================================================
// BEHAVIOURAL tests for the Five-Card Draw fold/opening calibration (D-082).
//
// These deliberately assert on what the bots DO, not on the value of a lever: a
// lever value is an implementation detail we expect to keep tuning, whereas
// "the rock does not walk away before it has seen its new cards" is the property
// the player actually experiences. Tests that pin lever values would have to be
// rewritten at every calibration and would not have caught this defect — the old
// levers were all "correct" while the behaviour was absurd.

import XCTest
@testable import GameWorld
@testable import GameEngine

final class DrawCalibrationTests: XCTestCase {

    private let whiskey = WorldPersonalities.riverwoodWhiskey
    private var novice: Personality { whiskey[0] }
    private var rock: Personality { whiskey[1] }
    private var aggressor: Personality { whiskey[2] }

    /// A random legal five-card holding.
    private func randomFive(_ rng: inout SeededGenerator) -> [Card] {
        var deck = Deck()
        deck.shuffle(seed: rng.next())
        return (0..<5).compactMap { _ in deck.draw() }
    }

    /// A first-round betting spot at the Whiskey's real stakes: 4 antes of 25 in the
    /// pot, facing one small bet of 50.
    private func firstRoundFacingABet(_ cards: [Card]) -> DrawBotContext {
        let legal = DrawLegalActions(seatID: 0, canFold: true, canCheck: false, canCall: true,
                                     callAmount: 50, canBet: false, canRaise: true,
                                     betUnit: 50, raisesRemaining: 3, hasOpeners: true)
        return DrawBotContext(heroSeatID: 0, cards: cards, phase: .firstBet, potSize: 150,
                              currentBet: 50, toCall: 50, heroStack: 2000, legal: legal,
                              seats: [], activeOpponents: 3, lateness: 0.5)
    }

    private func openingSpot(_ cards: [Card], hasOpeners: Bool, opponents: Int = 3) -> DrawBotContext {
        let legal = DrawLegalActions(seatID: 0, canFold: true, canCheck: true, canCall: false,
                                     callAmount: 0, canBet: true, canRaise: false,
                                     betUnit: 50, raisesRemaining: 3, hasOpeners: hasOpeners)
        return DrawBotContext(heroSeatID: 0, cards: cards, phase: .firstBet, potSize: 100,
                              currentBet: 0, toCall: 0, heroStack: 2000, legal: legal,
                              seats: [], activeOpponents: opponents, lateness: 0.5)
    }

    /// Runs `count` random first-round spots and reports the fold rate, plus the fold
    /// rate restricted to hands of at least `floor`.
    private func foldRates(_ p: Personality, count: Int = 600,
                           seed: UInt64 = 4242) -> (all: Double, madeHands: Double) {
        let bot = HeuristicDrawBot(personality: p, seed: 9)
        var rng = SeededGenerator(seed: seed)
        var folds = 0, madeFolds = 0, made = 0
        for _ in 0..<count {
            let cards = randomFive(&rng)
            // "Made hand" here uses the GAME'S OWN bar: jacks-or-better, the holding
            // this variant considers worth playing. A pair of deuces folding to a bet
            // three-handed is ordinary poker, not the defect.
            let ev = HandEvaluator.evaluate(cards)
            let isMade = ev.category > .pair ||
                (ev.category == .pair && (ev.tiebreakers.first ?? 0) >= Rank.jack.rawValue)
            if isMade { made += 1 }
            if case .fold = bot.decideAction(firstRoundFacingABet(cards)) {
                folds += 1
                if isMade { madeFolds += 1 }
            }
        }
        return (Double(folds) / Double(count), Double(madeFolds) / Double(max(1, made)))
    }

    // MARK: - The defect the player reported: folding before the exchange

    /// THE headline behaviour (D-082): at these stakes seeing the exchange costs one
    /// small bet into a pot of three antes, so walking away from a MADE hand before
    /// the draw is economically absurd. The rock used to fold 98% of pairs and 93% of
    /// two pair here; it must now overwhelmingly stay.
    func testRockDoesNotFoldMadeHandsBeforeTheExchange() {
        let rates = foldRates(rock)
        XCTAssertLessThan(rates.madeHands, 0.25,
                          "The rock folds \(Int(rates.madeHands * 100))% of jacks-or-better before the draw")
    }

    /// The same property for the whole roster: nobody throws away a made hand pre-draw
    /// at a limit table with a small bet.
    func testNobodyFoldsMadeHandsWholesaleBeforeTheExchange() {
        for (name, p) in [("novice", novice), ("rock", rock), ("aggressor", aggressor)] {
            let rates = foldRates(p)
            XCTAssertLessThan(rates.madeHands, 0.30,
                              "\(name) folds \(Int(rates.madeHands * 100))% of jacks-or-better pre-draw")
        }
    }

    /// The root cause, pinned directly (D-082): the betting decision must run on a real
    /// EQUITY scale, not on the category-ordinal `strength` score. A pair of aces wins
    /// far more often than the 0.20 the ordinal score gives it, and comparing that 0.20
    /// against a pot-odds bar is what made everyone fold.
    func testEquityIsOnAnEquityScaleNotACategoryScale() {
        let acesUp = [Card(.ace, .spades), Card(.ace, .hearts),
                      Card(.seven, .clubs), Card(.four, .diamonds), Card(.two, .spades)]
        var rng = SeededGenerator(seed: 1)
        let equity = DrawStrategy.equity(cards: acesUp, opponents: 3, drawToCome: true,
                                         samples: 400, using: &rng)
        XCTAssertGreaterThan(equity, 0.40, "A pair of aces must read as a real favourite")
        XCTAssertGreaterThan(equity, DrawStrategy.strength(acesUp) * 2,
                             "Equity must not collapse onto the ordinal category score")
    }

    /// Pre-draw equity must PLAY THE EXCHANGE FORWARD: a four-flush is nothing as a made
    /// hand (high card) but is a genuine holding before the draw. That is the whole point
    /// of the first round.
    func testPreDrawEquityCountsTheDrawToCome() {
        let fourFlush = [Card(.king, .spades), Card(.nine, .spades), Card(.seven, .spades),
                         Card(.four, .spades), Card(.two, .hearts)]
        var a = SeededGenerator(seed: 2), b = SeededGenerator(seed: 2)
        let withDraw = DrawStrategy.equity(cards: fourFlush, opponents: 3, drawToCome: true,
                                           samples: 400, using: &a)
        let asMade = DrawStrategy.equity(cards: fourFlush, opponents: 3, drawToCome: false,
                                         samples: 400, using: &b)
        XCTAssertGreaterThan(withDraw, asMade,
                             "A four-flush must be worth more before the exchange than as a dead high card")
    }

    // MARK: - The aggressor and the opening requirement

    /// Jacks-or-better is a RULE, not a strategic option (D-082): an open on air can only
    /// win by folding everyone out, and reaching showdown is an automatic loss. The
    /// aggressor used to open on air 36% of the time while opening legitimately only 3%
    /// — the exact inversion. It must now open FAR more often with the goods than without.
    func testAggressorOpensMostlyWhenItActuallyHoldsOpeners() {
        let bot = HeuristicDrawBot(personality: aggressor, seed: 9)
        var rng = SeededGenerator(seed: 777)
        var airSpots = 0, airOpens = 0, openerSpots = 0, legitOpens = 0
        for _ in 0..<600 {
            let cards = randomFive(&rng)
            let ev = HandEvaluator.evaluate(cards)
            let hasOpeners = ev.category > .pair ||
                (ev.category == .pair && (ev.tiebreakers.first ?? 0) >= Rank.jack.rawValue)
            let action = bot.decideAction(openingSpot(cards, hasOpeners: hasOpeners))
            if hasOpeners {
                openerSpots += 1
                if case .bet = action { legitOpens += 1 }
            } else {
                airSpots += 1
                if case .bet = action { airOpens += 1 }
            }
        }
        let airRate = Double(airOpens) / Double(max(1, airSpots))
        let legitRate = Double(legitOpens) / Double(max(1, openerSpots))
        XCTAssertLessThan(airRate, 0.10,
                          "The aggressor still bluff-opens without openers \(Int(airRate * 100))% of the time")
        XCTAssertGreaterThan(legitRate, airRate * 3,
                             "The aggressor must open far more often WITH openers than without")
    }

    /// The fix is structural, not a lobotomy: a light open is a real weapon HEADS-UP
    /// (where folding everyone out is plausible) and a losing move multi-way. The
    /// aggressor's reckless `openingDiscipline` is deliberately left untouched.
    func testLightOpeningSurvivesHeadsUpAndCollapsesMultiWay() {
        let bot = HeuristicDrawBot(personality: aggressor, seed: 9)
        func airOpenRate(opponents: Int) -> Double {
            var rng = SeededGenerator(seed: 31)
            var spots = 0, opens = 0
            for _ in 0..<600 {
                let cards = randomFive(&rng)
                let ev = HandEvaluator.evaluate(cards)
                let hasOpeners = ev.category > .pair ||
                    (ev.category == .pair && (ev.tiebreakers.first ?? 0) >= Rank.jack.rawValue)
                guard !hasOpeners else { continue }
                spots += 1
                if case .bet = bot.decideAction(openingSpot(cards, hasOpeners: false,
                                                            opponents: opponents)) { opens += 1 }
            }
            return Double(opens) / Double(max(1, spots))
        }
        XCTAssertGreaterThan(airOpenRate(opponents: 1), airOpenRate(opponents: 3),
                             "A light open must stay a heads-up weapon, not a multi-way suicide")
        XCTAssertEqual(aggressor.openingDiscipline, 0.20, accuracy: 0.001,
                       "The aggressor's character lever must NOT be dulled to fix this")
    }

    /// The rock's signature is intact: it never opens without provable openers.
    func testRockNeverOpensOnAir() {
        let bot = HeuristicDrawBot(personality: rock, seed: 9)
        var rng = SeededGenerator(seed: 88)
        var opens = 0
        for _ in 0..<400 {
            let cards = randomFive(&rng)
            if case .bet = bot.decideAction(openingSpot(cards, hasOpeners: false)) { opens += 1 }
        }
        XCTAssertLessThanOrEqual(opens, 2, "The rock must essentially never open on air")
    }

    // MARK: - The rock must stay killable, without becoming a different animal

    /// A rock that puts almost nothing in play cannot be beaten — it is a wall, not a
    /// hard opponent (D-082). Its chips must actually circulate.
    func testRockChipsCirculate() async throws {
        func provider(_ p: Personality, _ s: UInt64) -> DrawBotActionProvider {
            DrawBotActionProvider(HeuristicDrawBot(personality: p, seed: s))
        }
        let r = DrawTableRules.riverwoodWhiskey
        var grossOutflow = 0, deals = 0
        for seed in UInt64(1)...3 {
            let driver = DrawSessionDriver(capacity: 4, seats: [
                DrawSeatAssignment(position: 0, playerID: 0, chips: 2000, provider: provider(novice, seed * 11)),
                DrawSeatAssignment(position: 1, playerID: 1, chips: 2000, provider: provider(rock, seed * 22)),
                DrawSeatAssignment(position: 2, playerID: 2, chips: 2000, provider: provider(aggressor, seed * 33)),
                DrawSeatAssignment(position: 3, playerID: 3, chips: 2000, provider: provider(novice, seed * 44)),
            ], buttonPosition: 0, ante: r.ante, smallBet: r.smallBet, bigBet: r.bigBet, seed: seed)
            var previous = 2000
            for outcome in try await driver.run(maxHands: 40) {
                let now = outcome.chipsByPlayer[1] ?? 0
                grossOutflow += max(0, previous - now)
                previous = now
                deals += 1
            }
        }
        let perDeal = Double(grossOutflow) / Double(max(1, deals))
        XCTAssertGreaterThan(perDeal, Double(r.ante),
                             "The rock only bleeds \(Int(perDeal))/deal — it is barely reachable")
    }

    // MARK: - Distinctness survives the recalibration

    /// The recalibration must NOT flatten the roster toward the middle: the three
    /// characters must remain ordered and clearly apart on the axis that defines them.
    func testPersonalitiesRemainRecognisablyDistinct() {
        let n = foldRates(novice).all
        let r = foldRates(rock).all
        let a = foldRates(aggressor).all
        XCTAssertGreaterThan(r, n, "The rock must still be tighter than the novice")
        XCTAssertGreaterThan(n, a, "The novice must still be tighter than the aggressor")
        XCTAssertGreaterThan(r - a, 0.20,
                             "Rock and aggressor collapsed to \(Int(r * 100))% vs \(Int(a * 100))% — too close")
        // Signature dials untouched by the calibration.
        XCTAssertLessThan(rock.bluffFrequency, 0.06, "The rock must still essentially never bluff")
        XCTAssertGreaterThan(rock.openingDiscipline, 0.90, "The rock must still respect the opening rule")
        XCTAssertGreaterThan(aggressor.aggression, 0.85, "The aggressor must still be the aggressor")
        XCTAssertLessThan(novice.pressureResistance, 0.45, "The novice must still be bullyable")
    }
}
