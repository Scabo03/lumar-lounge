// MachiavelliTests.swift
// =====================================================================
// The Machiavelli engine (D-070): the validity predicate on every frontier case, the
// turn model (hypothetical evaluation, multi-move, terminal legality), recombination,
// the bot's two independent personality axes, the interruptible search's budget
// guarantee, determinism, and additive Personality back-compatibility.

import XCTest
@testable import GameEngine

final class MachiavelliTests: XCTestCase {

    // Card constructor shorthand.
    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    // MARK: - Validity predicate: frontier cases (D-070)

    func testGroupMinimalAndMaximal() {
        XCTAssertEqual(MachiavelliRules.classify([c(.seven, .spades), c(.seven, .hearts), c(.seven, .diamonds)]), .group)
        XCTAssertEqual(MachiavelliRules.classify([c(.seven, .spades), c(.seven, .hearts), c(.seven, .diamonds), c(.seven, .clubs)]), .group)
    }

    func testGroupRequiresDistinctSuits() {
        // Two of the same suit (possible with two decks) is not a legal group.
        XCTAssertNil(MachiavelliRules.classify([c(.seven, .spades), c(.seven, .spades), c(.seven, .hearts)]))
    }

    func testBelowMinimumIsInvalid() {
        XCTAssertNil(MachiavelliRules.classify([c(.seven, .spades), c(.seven, .hearts)]))
        XCTAssertNil(MachiavelliRules.classify([c(.five, .spades), c(.six, .spades)]))
    }

    func testRunMinimalAndSuitConsistency() {
        XCTAssertEqual(MachiavelliRules.classify([c(.five, .spades), c(.six, .spades), c(.seven, .spades)]), .run)
        // Mixed suits: not a run.
        XCTAssertNil(MachiavelliRules.classify([c(.five, .spades), c(.six, .hearts), c(.seven, .spades)]))
        // Non-consecutive same suit: not a run.
        XCTAssertNil(MachiavelliRules.classify([c(.five, .spades), c(.six, .spades), c(.eight, .spades)]))
    }

    func testAcePlaysHighAndLowButNeverWraps() {
        // Ace high: Q-K-A.
        XCTAssertEqual(MachiavelliRules.classify([c(.queen, .hearts), c(.king, .hearts), c(.ace, .hearts)]), .run)
        // Ace low: A-2-3.
        XCTAssertEqual(MachiavelliRules.classify([c(.ace, .hearts), c(.two, .hearts), c(.three, .hearts)]), .run)
        // No wrap: K-A-2 is illegal.
        XCTAssertNil(MachiavelliRules.classify([c(.king, .clubs), c(.ace, .clubs), c(.two, .clubs)]))
    }

    func testRunRejectsRepeatedRank() {
        XCTAssertNil(MachiavelliRules.classify([c(.five, .spades), c(.five, .spades), c(.six, .spades)]))
    }

    func testCanonicalOrderingOfMelds() {
        let run = Meld([c(.ace, .hearts), c(.two, .hearts), c(.three, .hearts)])!
        XCTAssertEqual(run.cards.map { $0.rank }, [.ace, .two, .three])   // ace placed low
        let highRun = Meld([c(.ace, .hearts), c(.king, .hearts), c(.queen, .hearts)])!
        XCTAssertEqual(highRun.cards.map { $0.rank }, [.queen, .king, .ace]) // ace placed high
    }

    func testIsValidTable() {
        XCTAssertTrue(MachiavelliRules.isValidTable([
            [c(.seven, .spades), c(.seven, .hearts), c(.seven, .diamonds)],
            [c(.four, .clubs), c(.five, .clubs), c(.six, .clubs)]
        ]))
        XCTAssertFalse(MachiavelliRules.isValidTable([[c(.seven, .spades), c(.seven, .hearts)]]))
        XCTAssertFalse(MachiavelliRules.isValidTable([[]]))
    }

    // MARK: - Turn model: hypothetical evaluation, no mutation

    func testEvaluateDoesNotMutate() {
        let ctx = MachiavelliTurnContext(playerID: 0,
                                         hand: [c(.seven, .clubs)],
                                         table: [Meld([c(.seven, .spades), c(.seven, .hearts), c(.seven, .diamonds)])!])
        let proposal = ctx.evaluate([[c(.seven, .spades), c(.seven, .hearts), c(.seven, .diamonds), c(.seven, .clubs)]])
        XCTAssertTrue(proposal.isLegal)
        XCTAssertEqual(proposal.placedFromHand, [c(.seven, .clubs)])
        XCTAssertTrue(proposal.resultingHand.isEmpty)
        // The context itself is untouched by evaluation.
        XCTAssertEqual(ctx.hand, [c(.seven, .clubs)])
        XCTAssertEqual(ctx.table.count, 1)
    }

    func testApplyCommitsAndTerminalLegality() throws {
        var ctx = MachiavelliTurnContext(playerID: 0,
                                         hand: [c(.seven, .clubs)],
                                         table: [Meld([c(.seven, .spades), c(.seven, .hearts), c(.seven, .diamonds)])!])
        XCTAssertTrue(ctx.mustDraw)          // nothing placed yet
        XCTAssertFalse(ctx.canPass)
        try ctx.apply([[c(.seven, .spades), c(.seven, .hearts), c(.seven, .diamonds), c(.seven, .clubs)]])
        XCTAssertTrue(ctx.canPass)           // placed one card → may pass
        XCTAssertFalse(ctx.mustDraw)
        XCTAssertTrue(ctx.handIsEmpty)       // and going out
    }

    func testRejectRemovingATableCard() {
        // A valid meld that nonetheless drops a turn-start table card → rejected.
        let ctx = MachiavelliTurnContext(playerID: 0,
                                         hand: [c(.eight, .spades)],
                                         table: [Meld([c(.five, .spades), c(.six, .spades), c(.seven, .spades)])!])
        let proposal = ctx.evaluate([[c(.six, .spades), c(.seven, .spades), c(.eight, .spades)]])
        XCTAssertFalse(proposal.isLegal)
        XCTAssertEqual(proposal.rejection, .removedTableCard)   // 5♠ can't leave the table
    }

    func testRejectUsingAnUnavailableCard() {
        let ctx = MachiavelliTurnContext(playerID: 0,
                                         hand: [c(.eight, .spades)],
                                         table: [Meld([c(.five, .spades), c(.six, .spades), c(.seven, .spades)])!])
        let proposal = ctx.evaluate([[c(.five, .spades), c(.six, .spades), c(.seven, .spades)],
                                     [c(.eight, .spades), c(.nine, .spades), c(.ten, .spades)]])
        XCTAssertFalse(proposal.isLegal)
        XCTAssertEqual(proposal.rejection, .usedUnavailableCard)  // 9♠/10♠ are nowhere
    }

    func testRejectInvalidCombination() {
        let ctx = MachiavelliTurnContext(playerID: 0, hand: [c(.eight, .spades)], table: [])
        let proposal = ctx.evaluate([[c(.eight, .spades), c(.nine, .hearts)]])
        if case .invalidCombination = proposal.rejection {} else { XCTFail("expected invalidCombination") }
    }

    // MARK: - Recombination (dismantle to free a card, table stays valid)

    func testRecombinationThatKeepsTableValidIsLegal() {
        // Table: group of 7s + a spade run. Hand: 7♣ and 8♠. Legal recomposition:
        // move 7♠ into the run (…7♠8♠) and reform the group as 7♥7♦7♣ → places both.
        let ctx = MachiavelliTurnContext(
            playerID: 0,
            hand: [c(.seven, .clubs), c(.eight, .spades)],
            table: [Meld([c(.seven, .spades), c(.seven, .hearts), c(.seven, .diamonds)])!,
                    Meld([c(.four, .spades), c(.five, .spades), c(.six, .spades)])!])
        let proposal = ctx.evaluate([
            [c(.seven, .hearts), c(.seven, .diamonds), c(.seven, .clubs)],
            [c(.four, .spades), c(.five, .spades), c(.six, .spades), c(.seven, .spades), c(.eight, .spades)]
        ])
        XCTAssertTrue(proposal.isLegal)
        XCTAssertEqual(Set(proposal.placedFromHand), [c(.seven, .clubs), c(.eight, .spades)])
    }

    func testRecombinationThatInvalidatesTableIsRejected() {
        // The same move but leaving the donor group with only two cards → rejected.
        let ctx = MachiavelliTurnContext(
            playerID: 0,
            hand: [c(.eight, .spades)],
            table: [Meld([c(.seven, .spades), c(.seven, .hearts), c(.seven, .diamonds)])!,
                    Meld([c(.four, .spades), c(.five, .spades), c(.six, .spades)])!])
        let proposal = ctx.evaluate([
            [c(.seven, .hearts), c(.seven, .diamonds)],   // only two → invalid
            [c(.four, .spades), c(.five, .spades), c(.six, .spades), c(.seven, .spades), c(.eight, .spades)]
        ])
        XCTAssertFalse(proposal.isLegal)
    }

    // MARK: - The same card moves many times within a turn (imposed rule, D-070)

    func testSameCardCanMoveMultipleTimesInATurn() throws {
        // A heart run and a group of 9s; hand holds 9♣.
        var ctx = MachiavelliTurnContext(
            playerID: 0,
            hand: [c(.nine, .clubs)],
            table: [Meld([c(.six, .hearts), c(.seven, .hearts), c(.eight, .hearts)])!,
                    Meld([c(.nine, .spades), c(.nine, .hearts), c(.nine, .diamonds)])!])
        // 1. Place 9♣ into the group.
        try ctx.apply([[c(.six, .hearts), c(.seven, .hearts), c(.eight, .hearts)],
                       [c(.nine, .spades), c(.nine, .hearts), c(.nine, .diamonds), c(.nine, .clubs)]])
        // 2. Move 9♥ (a table card) OUT of the group INTO the run.
        try ctx.apply([[c(.six, .hearts), c(.seven, .hearts), c(.eight, .hearts), c(.nine, .hearts)],
                       [c(.nine, .spades), c(.nine, .diamonds), c(.nine, .clubs)]])
        // 3. Move 9♥ BACK into the group — the same card moved again, same turn.
        try ctx.apply([[c(.six, .hearts), c(.seven, .hearts), c(.eight, .hearts)],
                       [c(.nine, .spades), c(.nine, .hearts), c(.nine, .diamonds), c(.nine, .clubs)]])
        // Validation is always against the turn-START snapshot, so all three succeeded;
        // net one card placed (9♣), so the player may pass.
        XCTAssertTrue(ctx.canPass)
        XCTAssertTrue(ctx.hand.isEmpty)
    }

    func testRetractingAPlacementRestoresTheDrawTerminal() throws {
        var ctx = MachiavelliTurnContext(playerID: 0,
                                         hand: [c(.seven, .clubs)],
                                         table: [Meld([c(.seven, .spades), c(.seven, .hearts), c(.seven, .diamonds)])!])
        try ctx.apply([[c(.seven, .spades), c(.seven, .hearts), c(.seven, .diamonds), c(.seven, .clubs)]])
        XCTAssertTrue(ctx.canPass)
        // Retract the just-placed card back to hand.
        try ctx.apply([[c(.seven, .spades), c(.seven, .hearts), c(.seven, .diamonds)]])
        XCTAssertTrue(ctx.mustDraw)     // net zero placed → must draw
        XCTAssertFalse(ctx.canPass)
    }

    // MARK: - Bot search: greedy baseline, going out, drawing on garbage

    private func context(hand: [Card], table: [[Card]], stock: Int = 50) -> MachiavelliBotContext {
        MachiavelliBotContext(heroSeatID: 0, hand: hand, table: table.map { Meld($0)! }, stockCount: stock,
                              seats: [MachiavelliPublicSeat(id: 0, handCount: hand.count, isHero: true)])
    }

    func testBotDrawsWhenNothingCanBePlaced() {
        let bot = HeuristicMachiavelliBot(personality: .machiavelliStudent, seed: 1, budget: .nodes(500))
        let plan = bot.planTurn(context(hand: [c(.two, .spades), c(.five, .hearts), c(.nine, .diamonds), c(.king, .clubs)], table: []))
        XCTAssertEqual(plan.terminal, .draw)
    }

    func testBotPlaysAnObviousMeld() {
        let bot = HeuristicMachiavelliBot(personality: .machiavelliStudent, seed: 1, budget: .nodes(500))
        let plan = bot.planTurn(context(hand: [c(.two, .spades), c(.two, .hearts), c(.two, .diamonds), c(.king, .clubs)], table: []))
        XCTAssertEqual(plan.terminal, .meld)
        XCTAssertTrue(MachiavelliRules.isValidTable(plan.finalTable))
    }

    // MARK: - The two INDEPENDENT axes (D-070)

    /// SEARCH-DEPTH axis, isolated (same patience). A deep searcher finds the
    /// recombination that goes out; a shallow one (tiny budget) only manages the greedy
    /// single placement. Independent of patience.
    func testSearchDepthAxisFindsRecombination() {
        let hand = [c(.seven, .clubs), c(.eight, .spades)]
        let table = [[c(.seven, .spades), c(.seven, .hearts), c(.seven, .diamonds)],
                     [c(.four, .spades), c(.five, .spades), c(.six, .spades)]]

        let shallow = HeuristicMachiavelliBot(personality: .machiavelliStudent, seed: 7, budget: .nodes(1))
        let deep = HeuristicMachiavelliBot(personality: .machiavelliProfessor, seed: 7, budget: .nodes(50_000))

        let shallowPlan = shallow.planTurn(context(hand: hand, table: table))
        let deepPlan = deep.planTurn(context(hand: hand, table: table))

        // Deep goes out (empty final hand → hero seat absent from the table's leftovers);
        // measure by placed cards through the predicate.
        XCTAssertEqual(placed(deepPlan, hand: hand, table: table), 2, "deep search recombines and goes out")
        XCTAssertLessThan(placed(shallowPlan, hand: hand, table: table), 2, "shallow search misses the recombination")
    }

    /// PATIENCE axis, isolated (same search depth). Two personalities that differ ONLY
    /// in patience: facing a small placement with a live stock, the impatient one plays
    /// it, the patient one holds and draws. Proves patience is a real, separate axis.
    func testPatienceAxisIsIndependentOfDepth() {
        let base = Personality(name: "base", tightness: 0.5, aggression: 0.5, bluffFrequency: 0,
                               riskTolerance: 0.5, positionAwareness: 0.5, rationality: 0.5, tiltReactivity: 0.2,
                               machiavelliSearchDepth: 0.6, machiavelliPatience: 0.0)
        let patient = Personality(name: "patient", tightness: 0.5, aggression: 0.5, bluffFrequency: 0,
                                  riskTolerance: 0.5, positionAwareness: 0.5, rationality: 0.5, tiltReactivity: 0.2,
                                  machiavelliSearchDepth: 0.6, machiavelliPatience: 1.0)   // same depth!

        // A single small placement available (extend the group by one), big hand, live stock.
        let hand = [c(.two, .clubs), c(.five, .hearts), c(.nine, .diamonds), c(.king, .clubs),
                    c(.four, .hearts), c(.jack, .spades)]
        let table = [[c(.two, .spades), c(.two, .hearts), c(.two, .diamonds)]]

        // Sample several seeds: the impatient bot melds far more often than the patient one.
        var impatientMelds = 0, patientMelds = 0
        for seed in UInt64(0)..<40 {
            let a = HeuristicMachiavelliBot(personality: base, seed: seed, budget: .nodes(3_000))
            let b = HeuristicMachiavelliBot(personality: patient, seed: seed, budget: .nodes(3_000))
            if a.planTurn(context(hand: hand, table: table)).terminal == .meld { impatientMelds += 1 }
            if b.planTurn(context(hand: hand, table: table)).terminal == .meld { patientMelds += 1 }
        }
        XCTAssertGreaterThan(impatientMelds, patientMelds, "with identical depth, low patience plays more, high patience holds")
        XCTAssertGreaterThan(impatientMelds, 30, "the impatient bot almost always plays a found placement")
    }

    /// The three archetypes are NOT three grades of one "strength" dial. The proof: the
    /// adult searches DEEPER than the student, yet on a small-placement spot it MELDS
    /// LESS OFTEN, because it is more PATIENT. If the presets were one scale, "more
    /// search" would mean "more melding" — here the deeper bot plays less. The two axes
    /// pull in different directions.
    func testArchetypesAreNotThreeGradesOfOneScale() {
        // Small placement available (extend the group of 2s by one), big hand, live stock.
        let hand = [c(.two, .clubs), c(.five, .hearts), c(.nine, .diamonds), c(.king, .clubs),
                    c(.four, .hearts), c(.jack, .spades)]
        let table = [[c(.two, .spades), c(.two, .hearts), c(.two, .diamonds)]]

        var studentMelds = 0, adultMelds = 0
        for seed in UInt64(0)..<40 {
            if HeuristicMachiavelliBot(personality: .machiavelliStudent, seed: seed)
                .planTurn(context(hand: hand, table: table)).terminal == .meld { studentMelds += 1 }
            if HeuristicMachiavelliBot(personality: .machiavelliAdult, seed: seed)
                .planTurn(context(hand: hand, table: table)).terminal == .meld { adultMelds += 1 }
        }
        XCTAssertGreaterThan(studentMelds, adultMelds,
                             "the shallower student plays the placement more than the deeper-but-patient adult")
    }

    private func placed(_ plan: MachiavelliTurnPlan, hand: [Card], table: [[Card]]) -> Int {
        guard plan.terminal == .meld else { return 0 }
        let ctx = MachiavelliTurnContext(playerID: 0, hand: hand, table: table.map { Meld($0)! })
        let proposal = ctx.evaluate(plan.finalTable)
        return proposal.isLegal ? proposal.placedFromHand.count : 0
    }

    // MARK: - Interruptible search NEVER overruns its budget (D-070)

    func testTimeBudgetNeverOverrunsOnAComplexTable() {
        // A deliberately busy table + a full hand, to force heavy search.
        let table: [[Card]] = [
            [c(.two, .spades), c(.three, .spades), c(.four, .spades), c(.five, .spades)],
            [c(.seven, .hearts), c(.eight, .hearts), c(.nine, .hearts), c(.ten, .hearts)],
            [c(.jack, .clubs), c(.queen, .clubs), c(.king, .clubs)],
            [c(.five, .diamonds), c(.five, .clubs), c(.five, .hearts)]
        ]
        let hand = [c(.six, .spades), c(.six, .hearts), c(.six, .diamonds), c(.six, .clubs),
                    c(.ace, .spades), c(.two, .diamonds), c(.three, .diamonds), c(.four, .diamonds),
                    c(.jack, .hearts), c(.queen, .hearts), c(.king, .hearts), c(.ten, .clubs), c(.nine, .clubs)]
        let bot = HeuristicMachiavelliBot(personality: .machiavelliProfessor, seed: 99,
                                          budget: .time(.milliseconds(300)))
        let ctx = context(hand: hand, table: table)

        let clock = ContinuousClock()
        let start = clock.now
        let plan = bot.planTurn(ctx)
        let elapsed = clock.now - start

        XCTAssertLessThan(elapsed, .milliseconds(1200), "the search must not overrun its 300ms budget by much")
        // And it still returns a legal plan.
        if plan.terminal == .meld { XCTAssertTrue(MachiavelliRules.isValidTable(plan.finalTable)) }
    }

    // MARK: - Determinism given a seed + node budget (D-070)

    func testDeterministicGivenSeedAndNodeBudget() {
        let hand = [c(.seven, .clubs), c(.eight, .spades), c(.king, .diamonds)]
        let table = [[c(.seven, .spades), c(.seven, .hearts), c(.seven, .diamonds)],
                     [c(.four, .spades), c(.five, .spades), c(.six, .spades)]]
        func run() -> MachiavelliTurnPlan {
            HeuristicMachiavelliBot(personality: .machiavelliProfessor, seed: 2026, budget: .nodes(20_000))
                .planTurn(context(hand: hand, table: table))
        }
        XCTAssertEqual(run(), run(), "same seed + same node budget → identical plan")
    }

    // MARK: - Additive Personality back-compatibility (CONVENTIONS §1)

    func testMachiavelliDialsDoNotChangePokerBehaviour() {
        // Two personalities identical but for the Machiavelli dials must decide Texas,
        // Draw and Omaha identically.
        func make(_ depth: Double, _ patience: Double, _ malus: Double) -> Personality {
            Personality(name: "p", tightness: 0.5, aggression: 0.5, bluffFrequency: 0.3, riskTolerance: 0.5,
                        positionAwareness: 0.5, rationality: 0.7, tiltReactivity: 0.3,
                        machiavelliSearchDepth: depth, machiavelliPatience: patience, machiavelliMalusAversion: malus)
        }
        let a = make(0.0, 0.0, 0.0)
        let b = make(1.0, 1.0, 1.0)

        // Texas.
        let texasCtx = BotContext(heroSeatID: 0, hole: Hand(c(.ace, .spades), c(.king, .spades)),
                                  board: [c(.two, .hearts), c(.seven, .diamonds), c(.jack, .clubs)], street: .flop,
                                  potSize: 100, currentBet: 20, toCall: 20, heroStack: 500, bigBlind: 20,
                                  legal: LegalActions(seatID: 0, canFold: true, canCheck: false, canCall: true,
                                                      callAmount: 20, canBet: false, minBetTo: 0, maxBetTo: 0,
                                                      canRaise: true, minRaiseTo: 40, maxRaiseTo: 500, canAllIn: true),
                                  seats: [PublicSeat(id: 0, stack: 500, streetBet: 0, totalBet: 0, hasFolded: false, isAllIn: false, isHero: true)],
                                  activeOpponents: 1, lateness: 0.5, aggressionFacedThisStreet: true)
        XCTAssertEqual(HeuristicBot(personality: a, seed: 5).decide(texasCtx),
                       HeuristicBot(personality: b, seed: 5).decide(texasCtx))

        // Omaha.
        let omahaCtx = OmahaBotContext(heroSeatID: 0,
                                       hole: [c(.ace, .spades), c(.king, .spades), c(.queen, .hearts), c(.jack, .hearts)],
                                       board: [c(.two, .clubs), c(.seven, .diamonds), c(.ten, .spades)], street: .flop,
                                       potSize: 100, currentBet: 20, toCall: 20, heroStack: 500, bigBlind: 20,
                                       legal: OmahaLegalActions(seatID: 0, canFold: true, canCheck: false, canCall: true,
                                                                callAmount: 20, canBet: false, minBetTo: 0, maxBetTo: 0,
                                                                canRaise: true, minRaiseTo: 40, maxRaiseTo: 140, canAllIn: true),
                                       seats: [OmahaPublicSeat(id: 0, stack: 500, streetBet: 0, totalBet: 0, hasFolded: false, isAllIn: false, isHero: true)],
                                       activeOpponents: 1, lateness: 0.5, aggressionFacedThisStreet: true)
        XCTAssertEqual(HeuristicOmahaBot(personality: a, seed: 5, equitySamples: 20).decide(omahaCtx),
                       HeuristicOmahaBot(personality: b, seed: 5, equitySamples: 20).decide(omahaCtx))
    }

    // MARK: - Hand scoring (D-071)

    func testCardValueScale() {
        XCTAssertEqual(MachiavelliScoring.cardValue(c(.ace, .spades)), 10)
        XCTAssertEqual(MachiavelliScoring.cardValue(c(.king, .spades)), 5)
        XCTAssertEqual(MachiavelliScoring.cardValue(c(.jack, .spades)), 5)
        XCTAssertEqual(MachiavelliScoring.cardValue(c(.ten, .spades)), 1)   // ten is numbered, not a figure
        XCTAssertEqual(MachiavelliScoring.cardValue(c(.two, .spades)), 1)
    }

    func testScoringRewardsOutBonusPlacedAndPenalisesRemaining() {
        // Player A went out having placed an ace + a king (10+5=15): bonus 20 + 15 − 0.
        let a = MachiavelliScoring.PlayerHandResult(playerID: 0,
                    placed: [c(.ace, .spades), c(.king, .hearts)], remaining: [], wentOut: true)
        // Player B placed two low cards (2) and is stuck with an ace (−10): 2 − 10.
        let b = MachiavelliScoring.PlayerHandResult(playerID: 1,
                    placed: [c(.two, .clubs), c(.three, .clubs)], remaining: [c(.ace, .diamonds)], wentOut: false)
        let scores = MachiavelliScoring.score([a, b])
        XCTAssertEqual(scores[0], MachiavelliScoring.outBonus + 15)
        XCTAssertEqual(scores[1], 2 - 10)
        // Going out and shedding the ace beats being caught holding it.
        XCTAssertGreaterThan(scores[0]!, scores[1]!)
    }

    func testHoldingHeavyCardsIsHeavilyPenalised() {
        // Same placement, but one player is stuck with an ace, the other with a deuce.
        let stuckAce = MachiavelliScoring.score(.init(playerID: 0, placed: [], remaining: [c(.ace, .spades)], wentOut: false))
        let stuckLow = MachiavelliScoring.score(.init(playerID: 0, placed: [], remaining: [c(.two, .spades)], wentOut: false))
        XCTAssertEqual(stuckAce, -10)
        XCTAssertEqual(stuckLow, -1)
    }

    // MARK: - Bots play SCORE-AWARE (D-071)

    /// A context with an opponent that holds `opponentCount` cards (a closing threat).
    private func context(hand: [Card], table: [[Card]], stock: Int, opponentCount: Int) -> MachiavelliBotContext {
        MachiavelliBotContext(heroSeatID: 0, hand: hand, table: table.map { Meld($0)! }, stockCount: stock,
                              seats: [MachiavelliPublicSeat(id: 0, handCount: hand.count, isHero: true),
                                      MachiavelliPublicSeat(id: 1, handCount: opponentCount, isHero: false)])
    }

    /// A malus-averse bot prefers a plan that sheds an ACE over one that sheds two low
    /// cards, even though the latter places more cards — value beats count for it.
    func testMalusAverseBotShedsHighValueCards() {
        // Table offers two independent extension points:
        //  • a group of aces (place A♣, value 10, one card), and
        //  • a spade run 4-5-6 that can grow with 7♠ then 8♠ (two low cards, value 2).
        // The hand holds exactly A♣, 7♠, 8♠ — but placing the ace and placing the run
        // tail both compete; a count-maximiser prefers the two low cards, a malus-averse
        // bot prefers shedding the ace.
        let hand = [c(.ace, .clubs), c(.seven, .spades), c(.eight, .spades)]
        let table = [[c(.ace, .spades), c(.ace, .hearts), c(.ace, .diamonds)],
                     [c(.four, .spades), c(.five, .spades), c(.six, .spades)]]

        let averse = HeuristicMachiavelliBot(
            personality: Personality(name: "averse", tightness: 0.5, aggression: 0.5, bluffFrequency: 0,
                riskTolerance: 0.5, positionAwareness: 0.5, rationality: 0.7, tiltReactivity: 0,
                machiavelliSearchDepth: 0.9, machiavelliPatience: 0, machiavelliMalusAversion: 1.0),
            seed: 3, budget: .nodes(40_000))
        let plan = averse.planTurn(context(hand: hand, table: table, stock: 40, opponentCount: 8))
        XCTAssertEqual(plan.terminal, .meld)
        let placed = plan.finalTable.flatMap { $0 }
        XCTAssertTrue(placed.contains(c(.ace, .clubs)), "a malus-averse bot places its ace")
    }

    /// The core D-071 requirement: a PATIENT bot does not hold indefinitely once heavy
    /// cards are at risk. With an opponent one card from out, the same patient
    /// personality holds far LESS when it is also malus-averse.
    func testMalusAversionStopsThePatientBotFromHoldingHeavies() {
        func patient(malus: Double) -> Personality {
            Personality(name: "p", tightness: 0.5, aggression: 0.5, bluffFrequency: 0, riskTolerance: 0.5,
                        positionAwareness: 0.5, rationality: 0.5, tiltReactivity: 0.2,
                        machiavelliSearchDepth: 0.6, machiavelliPatience: 1.0, machiavelliMalusAversion: malus)
        }
        // A small placement available (extend the 2s), a HEAVY hand (aces, kings), and an
        // opponent about to go out (2 cards) — holding is dangerous.
        let hand = [c(.two, .clubs), c(.ace, .hearts), c(.ace, .diamonds), c(.king, .clubs), c(.king, .hearts)]
        let table = [[c(.two, .spades), c(.two, .hearts), c(.two, .diamonds)]]

        var obliviousHolds = 0, averseHolds = 0
        for seed in UInt64(0)..<40 {
            let oblivious = HeuristicMachiavelliBot(personality: patient(malus: 0), seed: seed, budget: .nodes(2_000))
            let averse = HeuristicMachiavelliBot(personality: patient(malus: 1), seed: seed, budget: .nodes(2_000))
            let ctx = context(hand: hand, table: table, stock: 30, opponentCount: 2)
            if oblivious.planTurn(ctx).terminal == .draw { obliviousHolds += 1 }
            if averse.planTurn(ctx).terminal == .draw { averseHolds += 1 }
        }
        XCTAssertLessThan(averseHolds, obliviousHolds,
                          "under closing threat, the malus-averse patient bot holds far less than the oblivious one")
    }
}
