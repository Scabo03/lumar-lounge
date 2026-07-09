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
