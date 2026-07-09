import XCTest
@testable import GameEngine

final class BotTests: XCTestCase {

    // MARK: - Context builders (synthetic scenarios)

    /// Builds a preflop context for `hole` facing `toCall` more chips.
    private func facingBet(hole: Hand,
                           toCall: Int,
                           currentBet: Int,
                           pot: Int,
                           stack: Int,
                           bb: Int = 10,
                           lateness: Double = 0,
                           opponents: Int = 2,
                           board: [Card] = [],
                           tilt: Double = 0) -> BotContext {
        let heroStreetBet = currentBet - toCall
        let maxRaiseTo = heroStreetBet + stack
        let legal = LegalActions(
            seatID: 0,
            canFold: true,
            canCheck: false,
            canCall: true,
            callAmount: min(toCall, stack),
            canBet: false,
            minBetTo: 0,
            maxBetTo: 0,
            canRaise: maxRaiseTo > currentBet,
            minRaiseTo: min(currentBet + bb, maxRaiseTo),
            maxRaiseTo: maxRaiseTo,
            canAllIn: stack > 0
        )
        return BotContext(
            heroSeatID: 0, hole: hole, board: board,
            street: board.isEmpty ? .preflop : .flop,
            potSize: pot, currentBet: currentBet, toCall: toCall,
            heroStack: stack, bigBlind: bb, legal: legal,
            seats: [], activeOpponents: opponents, lateness: lateness,
            aggressionFacedThisStreet: currentBet > bb, emotionalTemperature: tilt
        )
    }

    /// Builds a context where the hero can check (no bet to call).
    private func canCheck(hole: Hand,
                          pot: Int,
                          stack: Int,
                          bb: Int = 10,
                          board: [Card] = [],
                          opponents: Int = 2,
                          tilt: Double = 0) -> BotContext {
        let legal = LegalActions(
            seatID: 0,
            canFold: true, canCheck: true, canCall: false, callAmount: 0,
            canBet: stack > 0, minBetTo: min(bb, stack), maxBetTo: stack,
            canRaise: false, minRaiseTo: 0, maxRaiseTo: 0, canAllIn: stack > 0
        )
        return BotContext(
            heroSeatID: 0, hole: hole, board: board,
            street: board.isEmpty ? .preflop : .flop,
            potSize: pot, currentBet: 0, toCall: 0,
            heroStack: stack, bigBlind: bb, legal: legal,
            seats: [], activeOpponents: opponents, lateness: 0,
            aggressionFacedThisStreet: false, emotionalTemperature: tilt
        )
    }

    private func card(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    private func isPermitted(_ action: Action, by legal: LegalActions) -> Bool {
        switch action {
        case .fold: return legal.canFold
        case .check: return legal.canCheck
        case .call: return legal.canCall
        case .bet(let n): return legal.canBet && n >= legal.minBetTo && n <= legal.maxBetTo
        case .raise(let n): return legal.canRaise && n >= legal.minRaiseTo && n <= legal.maxRaiseTo
        case .allIn: return legal.canAllIn
        }
    }

    // MARK: - Legality

    func testBotOnlyReturnsLegalActionsAcrossManyScenarios() {
        // Legality doesn't depend on equity precision — keep samples low for speed.
        let bots = Personality.starting.map { HeuristicBot(personality: $0, seed: 1, equitySamples: 30) }
        for bot in bots {
            for seed in UInt64(0)..<20 {
                // Vary the scenario a little through the pot/toCall.
                let ctxA = facingBet(hole: Hand(card(.ace, .spades), card(.king, .hearts)),
                                     toCall: 10 + Int(seed) * 3, currentBet: 10 + Int(seed) * 3,
                                     pot: 15 + Int(seed) * 5, stack: 500)
                let ctxB = canCheck(hole: Hand(card(.seven, .clubs), card(.two, .diamonds)),
                                    pot: 20 + Int(seed) * 4, stack: 500,
                                    board: [card(.king, .spades), card(.nine, .hearts), card(.four, .clubs)])
                XCTAssertTrue(isPermitted(bot.decide(ctxA), by: ctxA.legal))
                XCTAssertTrue(isPermitted(bot.decide(ctxB), by: ctxB.legal))
            }
        }
    }

    // MARK: - Determinism

    func testSameBotSameContextIsDeterministic() {
        let a = HeuristicBot(personality: .hotAggressor, seed: 42)
        let b = HeuristicBot(personality: .hotAggressor, seed: 42)
        let ctx = facingBet(hole: Hand(card(.queen, .hearts), card(.jack, .hearts)),
                            toCall: 40, currentBet: 40, pot: 60, stack: 800)
        XCTAssertEqual(a.decide(ctx), b.decide(ctx))
        // Postflop too, where Monte Carlo equity is involved.
        let ctx2 = canCheck(hole: Hand(card(.ace, .spades), card(.ace, .clubs)),
                            pot: 120, stack: 800,
                            board: [card(.ace, .hearts), card(.seven, .diamonds), card(.two, .clubs)])
        XCTAssertEqual(a.decide(ctx2), b.decide(ctx2))
    }

    // MARK: - Characterisation (personalities differ)

    func testDifferentPersonalitiesCanDifferInAnIdenticalSpot() {
        // A marginal hand (KTo) facing a raise: the rock gives up, looser/more
        // aggressive personalities do not.
        let ctx = facingBet(hole: Hand(card(.king, .diamonds), card(.ten, .spades)),
                            toCall: 20, currentBet: 30, pot: 45, stack: 1000, lateness: 0.2)
        let actions = Personality.starting.map { HeuristicBot(personality: $0, seed: 3).decide(ctx) }
        XCTAssertGreaterThanOrEqual(Set(actions).count, 2, "Personalities should not all act alike here")

        let rock = HeuristicBot(personality: .conservativeRock, seed: 3).decide(ctx)
        XCTAssertEqual(rock, .fold, "The rock folds a marginal hand to a raise")
    }

    // MARK: - Obvious spots

    func testEveryPersonalityAtLeastCallsWithAcesPreflop() {
        let aces = Hand(card(.ace, .spades), card(.ace, .hearts))
        for personality in Personality.starting {
            for seed in UInt64(0)..<12 {
                let ctx = facingBet(hole: aces, toCall: 10, currentBet: 10, pot: 15, stack: 1000)
                let action = HeuristicBot(personality: personality, seed: seed).decide(ctx)
                XCTAssertNotEqual(action, .fold, "\(personality.name) folded pocket aces (seed \(seed))")
            }
        }
    }

    func testRockAlwaysFoldsTrashWhileAggressorSometimesDoesnt() {
        let trash = Hand(card(.seven, .clubs), card(.two, .diamonds)) // 7-2 offsuit, the worst
        var aggressorNonFolds = 0
        for seed in UInt64(0)..<12 {
            let ctx = facingBet(hole: trash, toCall: 30, currentBet: 30, pot: 45, stack: 1000, lateness: 0)
            let rock = HeuristicBot(personality: .conservativeRock, seed: seed).decide(ctx)
            XCTAssertEqual(rock, .fold, "The rock should fold 7-2o (seed \(seed))")

            let aggressor = HeuristicBot(personality: .hotAggressor, seed: seed).decide(ctx)
            if aggressor != .fold { aggressorNonFolds += 1 }
        }
        XCTAssertGreaterThan(aggressorNonFolds, 0, "The aggressor should sometimes play 7-2o")
    }

    // MARK: - Tilt (emotional reactivity)

    func testTiltLoosensAReactivePersonality() {
        // Same marginal made hand; with a hot tilt a highly reactive bot should
        // continue more often than when calm. Count across seeds. The bet is kept
        // BELOW the 60%-pot pressure signal (D-048) and the spot is POST-flop, so
        // this isolates tilt from the pressure fold and the pre-flop trash fold.
        let hole = Hand(card(.eight, .spades), card(.five, .spades)) // weak, marginal
        let board = [card(.king, .clubs), card(.nine, .hearts), card(.four, .diamonds)]
        func continues(tilt: Double) -> Int {
            var count = 0
            for seed in UInt64(0)..<40 {
                // toCall 30 into a 90 pot ⇒ bet is 50% of the pot before it (< 60%),
                // a marginal spot where a calm bot often folds this weak holding.
                let ctx = facingBet(hole: hole, toCall: 30, currentBet: 30, pot: 90,
                                    stack: 800, board: board, tilt: tilt)
                if HeuristicBot(personality: .eagerNovice, seed: seed).decide(ctx) != .fold { count += 1 }
            }
            return count
        }
        XCTAssertGreaterThan(continues(tilt: 0.9), continues(tilt: 0.0),
                             "Tilt should make a reactive bot continue more often")
    }

    // MARK: - Pressure resistance (D-048)

    func testCallThresholdMultiplierMatchesCalibration() {
        // A small bet (≤ 60% of the pot) demands no extra equity.
        XCTAssertEqual(Personality.callThresholdMultiplier(betFraction: 0.5, pressureResistance: 0.3), 1.0)
        XCTAssertEqual(Personality.callThresholdMultiplier(betFraction: 0.6, pressureResistance: 0.3), 1.0)
        // A 70%-pot bet: pressure-shy demands ≈ +44%, stubborn ≈ +6%.
        let shy = Personality.callThresholdMultiplier(betFraction: 0.7, pressureResistance: 0.3)
        XCTAssertGreaterThan(shy, 1.35); XCTAssertLessThan(shy, 1.50)
        let stubborn = Personality.callThresholdMultiplier(betFraction: 0.7, pressureResistance: 0.9)
        XCTAssertGreaterThan(stubborn, 1.02); XCTAssertLessThan(stubborn, 1.12)
        XCTAssertLessThan(stubborn, shy, "a stubborn bot demands less extra equity than a shy one")
    }

    func testBigBetPressureMakesShyBotsFoldMoreThanStubbornOnes() {
        // Marginal equity (ace-high) POST-flop facing a pot-sized bet (100%>60%).
        let hole = Hand(card(.ace, .spades), card(.three, .diamonds))
        let board = [card(.king, .clubs), card(.nine, .hearts), card(.four, .diamonds)]
        func folds(_ p: Personality) -> Int {
            var f = 0
            for seed in UInt64(0)..<40 {
                let ctx = facingBet(hole: hole, toCall: 100, currentBet: 100, pot: 200,
                                    stack: 800, opponents: 1, board: board)
                if HeuristicBot(personality: p, seed: seed).decide(ctx) == .fold { f += 1 }
            }
            return f
        }
        let aggressor = folds(.hotAggressor)   // pressureResistance 0.75 → calls out of pride
        XCTAssertGreaterThan(folds(.conservativeRock), aggressor, "the rock folds to heavy pressure more than the aggressor")
        XCTAssertGreaterThan(folds(.eagerNovice), aggressor, "the scared novice folds to heavy pressure more than the aggressor")
    }

    func testStrongHandsNeverFoldToPressure() {
        // A monster (top set) never folds however big the bet — pressure only bites
        // marginal hands (D-048).
        let hole = Hand(card(.king, .spades), card(.king, .hearts))
        let board = [card(.king, .diamonds), card(.nine, .hearts), card(.four, .clubs)]
        for personality in Personality.starting {
            for seed in UInt64(0)..<12 {
                // Pot-sized bet: 300 into a 300 pot ⇒ potSize (incl. the bet) = 600.
                let ctx = facingBet(hole: hole, toCall: 300, currentBet: 300, pot: 600,
                                    stack: 1000, opponents: 1, board: board)
                XCTAssertNotEqual(HeuristicBot(personality: personality, seed: seed).decide(ctx), .fold,
                                  "\(personality.name) folded top set to pressure (seed \(seed))")
            }
        }
    }

    // MARK: - Trash fold (D-048)

    func testTrashFoldTendencyApproximatesTheFoldRate() {
        // A loose caller that would otherwise call any garbage, so the observed
        // fold rate on 7-2o isolates trashFoldTendency. Small bet → no pressure.
        func looseCaller(trash: Double) -> Personality {
            Personality(name: "Loose", tightness: 0.10, aggression: 0.0, bluffFrequency: 0.0,
                        riskTolerance: 0.90, positionAwareness: 0.0, rationality: 1.0,
                        tiltReactivity: 0.0, pressureResistance: 1.0, trashFoldTendency: trash)
        }
        let trash = Hand(card(.seven, .clubs), card(.two, .diamonds))   // the worst hand
        func foldRate(_ p: Personality) -> Double {
            var folds = 0; let n = 300
            for seed in UInt64(0)..<UInt64(n) {
                let ctx = facingBet(hole: trash, toCall: 10, currentBet: 10, pot: 60, stack: 800)
                if HeuristicBot(personality: p, seed: seed).decide(ctx) == .fold { folds += 1 }
            }
            return Double(folds) / Double(n)
        }
        // With trashFoldTendency 0.0 the loose caller never trash-folds (control).
        XCTAssertEqual(foldRate(looseCaller(trash: 0.0)), 0.0, accuracy: 0.001)
        XCTAssertEqual(foldRate(looseCaller(trash: 0.90)), 0.90, accuracy: 0.08)
        XCTAssertEqual(foldRate(looseCaller(trash: 0.20)), 0.20, accuracy: 0.08)
    }

    func testTrashFoldDoesNotFoldDecentHands() {
        // A strong hand is never trash-folded, whatever the tendency.
        let aces = Hand(card(.ace, .spades), card(.ace, .hearts))
        let p = Personality(name: "Disciplined", tightness: 0.5, aggression: 0.3, bluffFrequency: 0.1,
                            riskTolerance: 0.3, positionAwareness: 0.5, rationality: 1.0,
                            tiltReactivity: 0.0, trashFoldTendency: 1.0)
        for seed in UInt64(0)..<20 {
            let ctx = facingBet(hole: aces, toCall: 10, currentBet: 10, pot: 60, stack: 800)
            XCTAssertNotEqual(HeuristicBot(personality: p, seed: seed).decide(ctx), .fold,
                              "aces trash-folded (seed \(seed))")
        }
    }

    // MARK: - Honest information

    func testContextExposesOnlyHeroHoleCards() {
        let hand = HoldemHand(seats: [Seat(id: 0, stack: 1000),
                                      Seat(id: 1, stack: 1000),
                                      Seat(id: 2, stack: 1000)],
                              buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 77)
        let ctx = BotContext(actingIn: hand)!
        // The context's hole matches the acting seat's real hole…
        let heroReal = hand.seats.first { $0.id == ctx.heroSeatID }!.hole
        XCTAssertEqual(ctx.hole, heroReal)
        // …and the public seat view carries no cards at all (compile-time
        // guarantee: PublicSeat has no hole field). Sanity-check the count.
        XCTAssertEqual(ctx.seats.count, 3)
    }

    // MARK: - Multi-hand simulation

    func testMultiHandSimulationRunsWithoutCrashAndConservesChips() throws {
        // Three distinct personalities, three seats.
        let bots: [Int: PokerBot] = [
            0: HeuristicBot(personality: .eagerNovice, seed: 100, equitySamples: 40),
            1: HeuristicBot(personality: .conservativeRock, seed: 200, equitySamples: 40),
            2: HeuristicBot(personality: .hotAggressor, seed: 300, equitySamples: 40),
        ]
        var stacks: [Int: Int] = [0: 1000, 1: 1000, 2: 1000]
        let totalChips = stacks.values.reduce(0, +)

        var handNumber = 0
        while handNumber < 60 {
            let survivors = stacks.filter { $0.value > 0 }.keys.sorted()
            guard survivors.count >= 2 else { break }
            let seatConfigs = survivors.map { Seat(id: $0, stack: stacks[$0]!) }
            let button = handNumber % seatConfigs.count

            var hand = HoldemHand(seats: seatConfigs, buttonIndex: button,
                                  smallBlind: 5, bigBlind: 10, seed: UInt64(handNumber) &+ 1)

            var safety = 0
            while !hand.isComplete {
                safety += 1
                XCTAssertLessThan(safety, 5000, "Hand did not terminate")
                guard let ctx = BotContext(actingIn: hand) else { break }
                let action = bots[ctx.heroSeatID]!.decide(ctx)
                try hand.apply(action) // throws → an illegal action → test fails
            }

            // Carry the resulting stacks forward.
            for (id, stack) in hand.result!.finalStacks { stacks[id] = stack }
            // Chips are conserved every single hand.
            XCTAssertEqual(stacks.values.reduce(0, +), totalChips, "Chips not conserved after hand \(handNumber)")
            handNumber += 1
        }
        XCTAssertEqual(stacks.values.reduce(0, +), totalChips)
    }
}
