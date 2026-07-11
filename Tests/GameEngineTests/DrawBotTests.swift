import XCTest
@testable import GameEngine

/// Tests for the Five-Card Draw bot layer: the extended personality dimensions,
/// legal/deterministic decisions, the textbook discard heuristic, and a full
/// bot-driven multi-deal simulation that must never act illegally or lose chips.
final class DrawBotTests: XCTestCase {

    private func seats(_ stacks: [Int]) -> [DrawSeat] {
        stacks.enumerated().map { DrawSeat(id: $0.offset, stack: $0.element) }
    }

    private func deal(seed: UInt64, carry: Int = 0) -> FiveCardDrawHand {
        FiveCardDrawHand(seats: seats([1000, 1000, 1000, 1000]), buttonIndex: 0,
                         ante: 10, smallBet: 20, bigBet: 40, seed: seed, carryPot: carry)
    }

    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    // MARK: - Personality dimensions

    func testPresetsCarrySensibleDrawDimensions() {
        let rock = Personality.conservativeRock
        XCTAssertGreaterThan(rock.drawDiscipline, 0.7)
        XCTAssertLessThan(rock.drawBluffiness, 0.2)
        XCTAssertGreaterThan(rock.openingDiscipline, 0.8)

        let novice = Personality.eagerNovice
        XCTAssertLessThan(novice.drawDiscipline, 0.4)
        XCTAssertLessThan(novice.drawBluffiness, 0.3)

        let aggressor = Personality.hotAggressor
        XCTAssertGreaterThan(aggressor.drawBluffiness, 0.6)
        XCTAssertLessThan(aggressor.openingDiscipline, 0.4)
    }

    func testDrawDimensionsDefaultForTexasPersonalities() {
        // A personality built without the draw dials still gets sensible defaults
        // (the Texas fast-table bots rely on this).
        let p = Personality(name: "Test", tightness: 0.5, aggression: 0.5, bluffFrequency: 0.5,
                            riskTolerance: 0.5, positionAwareness: 0.5, rationality: 0.5,
                            tiltReactivity: 0.5)
        XCTAssertEqual(p.drawDiscipline, 0.5)
        XCTAssertEqual(p.drawBluffiness, 0.3)
        XCTAssertEqual(p.openingDiscipline, 0.7)
    }

    // MARK: - Fold-propensity dimensions in the Draw (D-048)

    /// Builds a facing-a-bet context for the given phase, pot and to-call, with an
    /// optional decisive-hand boost (D-053).
    private func facingBet(cards: [Card], phase: DrawPhase, currentBet: Int, potSize: Int,
                           aggressionBonus: Double = 0, trashFoldScale: Double = 1) -> DrawBotContext {
        let legal = DrawLegalActions(seatID: 0, canFold: true, canCheck: false, canCall: true,
                                     callAmount: currentBet, canBet: false, canRaise: true,
                                     betUnit: phase == .secondBet ? 40 : 20, raisesRemaining: 3, hasOpeners: true)
        return DrawBotContext(heroSeatID: 0, cards: cards, phase: phase, potSize: potSize,
                              currentBet: currentBet, toCall: currentBet, heroStack: 800, legal: legal,
                              seats: [], activeOpponents: 1, lateness: 0.5,
                              aggressionBonus: aggressionBonus, trashFoldScale: trashFoldScale)
    }

    // MARK: - Decisive-hand contextual boost (D-053)

    func testDecisiveBoostHalvesTrashFolding() {
        // A loose caller that would otherwise call garbage, so the fold rate isolates
        // trashFoldTendency; the decisive scale of 0.5 should roughly halve it.
        let garbage = [c(.two, .spades), c(.seven, .hearts), c(.nine, .diamonds), c(.jack, .clubs), c(.king, .spades)]
        let p = Personality(name: "P", tightness: 0.1, aggression: 0.0, bluffFrequency: 0.0,
                            riskTolerance: 0.9, positionAwareness: 0.0, rationality: 1.0,
                            tiltReactivity: 0.0, pressureResistance: 1.0, trashFoldTendency: 0.8)
        func foldRate(scale: Double) -> Double {
            var f = 0; let n = 300
            for seed in UInt64(0)..<UInt64(n) {
                let ctx = facingBet(cards: garbage, phase: .firstBet, currentBet: 20, potSize: 120, trashFoldScale: scale)
                if HeuristicDrawBot(personality: p, seed: seed).decideAction(ctx) == .fold { f += 1 }
            }
            return Double(f) / Double(n)
        }
        XCTAssertEqual(foldRate(scale: 1.0), 0.80, accuracy: 0.08)   // normal
        XCTAssertEqual(foldRate(scale: 0.5), 0.40, accuracy: 0.08)   // decisive: halved
    }

    func testDecisiveBoostRaisesTheValueRaiseRate() {
        // A strong made hand facing a bet: with the aggression bonus the bot raises
        // (rather than just calls) more often. No boost reproduces the base rate.
        let strong = [c(.ace, .spades), c(.ace, .hearts), c(.ace, .diamonds), c(.king, .clubs), c(.king, .spades)] // full house
        let p = Personality.eagerNovice
        func raiseRate(bonus: Double) -> Int {
            var r = 0
            for seed in UInt64(0)..<60 {
                let ctx = facingBet(cards: strong, phase: .secondBet, currentBet: 40, potSize: 120, aggressionBonus: bonus)
                if HeuristicDrawBot(personality: p, seed: seed).decideAction(ctx) == .raise { r += 1 }
            }
            return r
        }
        XCTAssertGreaterThan(raiseRate(bonus: 0.15), raiseRate(bonus: 0.0),
                             "the decisive aggression bonus should make the bot raise strong hands more")
    }

    func testSecondRoundBigBetPressureFoldsMoreForShyBots() {
        // A modest made hand (low trips) facing a pot-sized big bet after the draw —
        // strong enough to call a small bet, marginal against heavy pressure. Two
        // personalities identical but for pressureResistance: the shy one folds more.
        let hand = [c(.five, .spades), c(.five, .hearts), c(.five, .diamonds), c(.king, .clubs), c(.two, .spades)]
        func personality(pressure: Double) -> Personality {
            Personality(name: "P", tightness: 0.5, aggression: 0.3, bluffFrequency: 0.0,
                        riskTolerance: 0.4, positionAwareness: 0.5, rationality: 1.0,
                        tiltReactivity: 0.0, pressureResistance: pressure)
        }
        func folds(_ p: Personality) -> Int {
            var f = 0
            for seed in UInt64(0)..<40 {
                // 100 into a 100 pot ⇒ potSize (incl. the bet) = 200, bet = 100% of pot.
                let ctx = facingBet(cards: hand, phase: .secondBet, currentBet: 100, potSize: 200)
                if HeuristicDrawBot(personality: p, seed: seed).decideAction(ctx) == .fold { f += 1 }
            }
            return f
        }
        XCTAssertGreaterThan(folds(personality(pressure: 0.3)), folds(personality(pressure: 0.9)),
                             "a pressure-shy bot should fold the big post-draw bet more than a stubborn one")
    }

    func testFirstRoundTrashFoldFoldsGarbageMoreWhenDisciplined() {
        // A clearly weak pre-draw hand (no pair, no draw) facing a first-round bet:
        // the disciplined bot (high trashFoldTendency) folds it far more.
        let garbage = [c(.two, .spades), c(.seven, .hearts), c(.nine, .diamonds), c(.jack, .clubs), c(.king, .spades)]
        XCTAssertTrue(DrawStrategy.isPreDrawGarbage(garbage))
        func personality(trash: Double) -> Personality {
            Personality(name: "P", tightness: 0.1, aggression: 0.0, bluffFrequency: 0.0,
                        riskTolerance: 0.9, positionAwareness: 0.0, rationality: 1.0,
                        tiltReactivity: 0.0, pressureResistance: 1.0, trashFoldTendency: trash)
        }
        func foldRate(_ p: Personality) -> Double {
            var f = 0; let n = 200
            for seed in UInt64(0)..<UInt64(n) {
                let ctx = facingBet(cards: garbage, phase: .firstBet, currentBet: 20, potSize: 120)
                if HeuristicDrawBot(personality: p, seed: seed).decideAction(ctx) == .fold { f += 1 }
            }
            return Double(f) / Double(n)
        }
        XCTAssertEqual(foldRate(personality(trash: 0.0)), 0.0, accuracy: 0.02)
        XCTAssertGreaterThan(foldRate(personality(trash: 0.9)), 0.75,
                             "a disciplined bot folds most first-round garbage")
    }

    // MARK: - Textbook discards (pure strategy)

    func testOptimalDiscardsStandsPatOnMadeHands() {
        let flush = [c(.two, .hearts), c(.five, .hearts), c(.eight, .hearts), c(.jack, .hearts), c(.king, .hearts)]
        XCTAssertEqual(DrawStrategy.optimalDiscards(from: flush), [])
    }

    func testOptimalDiscardsKeepsThePair() {
        let pair = [c(.king, .spades), c(.king, .hearts), c(.two, .diamonds), c(.seven, .clubs), c(.nine, .spades)]
        let discards = DrawStrategy.optimalDiscards(from: pair)
        XCTAssertEqual(discards.count, 3)
        XCTAssertFalse(discards.contains { $0.rank == .king })   // never discards the pair
    }

    func testOptimalDiscardsKeepsTripsDiscardsTwo() {
        let trips = [c(.five, .spades), c(.five, .hearts), c(.five, .diamonds), c(.king, .clubs), c(.two, .spades)]
        let discards = DrawStrategy.optimalDiscards(from: trips)
        XCTAssertEqual(discards.count, 2)
        XCTAssertFalse(discards.contains { $0.rank == .five })
    }

    func testOptimalDiscardsDrawsOneToAFourFlush() {
        let fourFlush = [c(.two, .hearts), c(.five, .hearts), c(.eight, .hearts), c(.jack, .hearts), c(.king, .spades)]
        let discards = DrawStrategy.optimalDiscards(from: fourFlush)
        XCTAssertEqual(discards, [c(.king, .spades)])   // throw the off-suit card
    }

    // MARK: - Legality & determinism

    func testBotOnlyReturnsLegalBettingActions() {
        let bots = Personality.starting.map { HeuristicDrawBot(personality: $0, seed: 1) }
        for bot in bots {
            for seed in UInt64(0)..<40 {
                let hand = deal(seed: seed)
                let ctx = DrawBotContext(actingIn: hand)!
                let action = bot.decideAction(ctx)
                switch action {
                case .fold:  XCTAssertTrue(ctx.legal.canFold)
                case .check: XCTAssertTrue(ctx.legal.canCheck)
                case .call:  XCTAssertTrue(ctx.legal.canCall)
                case .bet:   XCTAssertTrue(ctx.legal.canBet)
                case .raise: XCTAssertTrue(ctx.legal.canRaise)
                }
            }
        }
    }

    func testBotDiscardsAreAlwaysLegal() throws {
        let bot = HeuristicDrawBot(personality: .eagerNovice, seed: 77)
        for seed in UInt64(0)..<40 {
            var hand = deal(seed: seed)
            while hand.phase == .firstBet {
                let legal = hand.legalActions()!
                try hand.apply(legal.canBet ? .bet : .call)
            }
            while hand.phase == .draw {
                let ctx = DrawDrawContext(drawingIn: hand)!
                let discards = bot.decideDiscards(ctx)
                XCTAssertLessThanOrEqual(discards.count, 4)
                XCTAssertEqual(Set(discards).count, discards.count)         // no repeats
                XCTAssertTrue(Set(discards).isSubset(of: Set(ctx.cards)))   // only held cards
                try hand.discard(discards)
            }
        }
    }

    func testBotIsDeterministic() throws {
        let a = HeuristicDrawBot(personality: .hotAggressor, seed: 42)
        let b = HeuristicDrawBot(personality: .hotAggressor, seed: 42)
        var hand = deal(seed: 5)
        let ctx = DrawBotContext(actingIn: hand)!
        XCTAssertEqual(a.decideAction(ctx), b.decideAction(ctx))
        // And the draw decision.
        while hand.phase == .firstBet {
            let legal = hand.legalActions()!
            try hand.apply(legal.canBet ? .bet : .call)
        }
        let dctx = DrawDrawContext(drawingIn: hand)!
        XCTAssertEqual(a.decideDiscards(dctx), b.decideDiscards(dctx))
    }

    // MARK: - Opening discipline characterisation

    func testDisciplinedBotNeverBluffOpensWhileAggressorSometimesDoes() {
        var rockOpens = 0, aggressorOpens = 0, samples = 0
        for seed in UInt64(0)..<400 {
            let hand = deal(seed: seed)
            let ctx = DrawBotContext(actingIn: hand)!
            guard !ctx.legal.hasOpeners else { continue }   // spots with NO openers
            samples += 1
            if HeuristicDrawBot(personality: .conservativeRock, seed: seed).decideAction(ctx) == .bet {
                rockOpens += 1
            }
            if HeuristicDrawBot(personality: .hotAggressor, seed: seed).decideAction(ctx) == .bet {
                aggressorOpens += 1
            }
        }
        XCTAssertGreaterThan(samples, 20, "should find plenty of no-opener spots")
        XCTAssertEqual(rockOpens, 0, "a disciplined bot never bluff-opens on air")
        XCTAssertGreaterThan(aggressorOpens, 0, "the aggressor sometimes gambles on opening light")
    }

    // MARK: - Full bot-driven simulation

    func testMultiDealSimulationRunsLegallyAndConservesChips() throws {
        let bots: [Int: DrawBot] = [
            0: HeuristicDrawBot(personality: .eagerNovice, seed: 100),
            1: HeuristicDrawBot(personality: .conservativeRock, seed: 200),
            2: HeuristicDrawBot(personality: .hotAggressor, seed: 300),
            3: HeuristicDrawBot(personality: .eagerNovice, seed: 400),
        ]
        var stacks: [Int: Int] = [0: 1000, 1: 1000, 2: 1000, 3: 1000]
        let total = stacks.values.reduce(0, +)
        var carry = 0

        var deal = 0
        while deal < 40 {
            let live = stacks.filter { $0.value > 0 }.keys.sorted()
            guard live.count >= 2 else { break }
            let configs = live.map { DrawSeat(id: $0, stack: stacks[$0]!) }
            let button = deal % configs.count
            var hand = FiveCardDrawHand(seats: configs, buttonIndex: button,
                                        ante: 10, smallBet: 20, bigBet: 40,
                                        seed: UInt64(deal) &+ 1, carryPot: carry)

            var safety = 0
            while !hand.isComplete {
                safety += 1
                XCTAssertLessThan(safety, 10_000, "deal did not terminate")
                if let sid = hand.actingSeatID {
                    let action = bots[sid]!.decideAction(DrawBotContext(actingIn: hand)!)
                    try hand.apply(action)         // throws on an illegal action → fail
                } else if hand.drawingSeatID != nil {
                    let ctx = DrawDrawContext(drawingIn: hand)!
                    try hand.discard(bots[ctx.heroSeatID]!.decideDiscards(ctx))
                } else {
                    break
                }
            }

            let result = hand.result!
            // Conservation: chips in stacks plus any carried pot are constant.
            let sumStacks = result.finalStacks.values.reduce(0, +)
            XCTAssertEqual(sumStacks + result.carriedPot, total, "chips not conserved after deal \(deal)")

            for (id, stack) in result.finalStacks { stacks[id] = stack }
            carry = result.outcome == .passedIn ? result.carriedPot : 0
            deal += 1
        }
        XCTAssertEqual(stacks.values.reduce(0, +) + carry, total)
    }
}
