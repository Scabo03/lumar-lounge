import XCTest
@testable import GameEngine

/// The Omaha bot and the new Personality dimensions (D-063): sensible default play,
/// and — critically — additive retro-compatibility (the Omaha dials do NOT change
/// Texas or Draw behaviour).
final class OmahaBotTests: XCTestCase {

    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    // MARK: - Preflop strength ranks Omaha holdings sensibly

    func testPreflopStrengthRewardsCoordination() {
        let premium = OmahaStrength.preflop([c(.ace, .spades), c(.ace, .hearts), c(.king, .spades), c(.king, .hearts)])
        let trash = OmahaStrength.preflop([c(.two, .clubs), c(.seven, .diamonds), c(.eight, .spades), c(.king, .hearts)])
        let quadsInHand = OmahaStrength.preflop([c(.ace, .spades), c(.ace, .hearts), c(.ace, .diamonds), c(.ace, .clubs)])
        XCTAssertGreaterThan(premium, trash, "AA-KK double-suited beats disconnected rainbow trash")
        XCTAssertGreaterThan(premium, quadsInHand, "four aces in hand (dead cards) is far weaker than AA-KK ds")
        XCTAssertTrue((0...1).contains(premium) && (0...1).contains(trash))
    }

    // MARK: - The Omaha dials shape play (default sanity, not calibration)

    private func preflopFacingBet(_ hole: [Card]) -> OmahaBotContext {
        let legal = OmahaLegalActions(seatID: 0, canFold: true, canCheck: false, canCall: true,
                                      callAmount: 10, canBet: false, minBetTo: 0, maxBetTo: 0,
                                      canRaise: true, minRaiseTo: 20, maxRaiseTo: 40, canAllIn: true)
        let seats = (0..<3).map { OmahaPublicSeat(id: $0, stack: 990, streetBet: $0 == 0 ? 0 : 10,
                                                  totalBet: $0 == 0 ? 0 : 10, hasFolded: false, isAllIn: false, isHero: $0 == 0) }
        return OmahaBotContext(heroSeatID: 0, hole: hole, board: [], street: .preflop, potSize: 20,
                               currentBet: 10, toCall: 10, heroStack: 990, bigBlind: 10, legal: legal,
                               seats: seats, activeOpponents: 2, lateness: 0.5, aggressionFacedThisStreet: true)
    }

    func testCoordinationDemandingBotFoldsTrashMoreOftenPreflop() {
        let trash = [c(.two, .clubs), c(.seven, .diamonds), c(.eight, .spades), c(.king, .hearts)]
        XCTAssertLessThan(OmahaStrength.preflop(trash), 0.35, "the test hand must be garbage for both bots")
        let ctx = preflopFacingBet(trash)

        func foldRate(_ p: Personality) -> Double {
            var folds = 0
            for seed in 0..<200 where HeuristicOmahaBot(personality: p, seed: UInt64(seed)).decide(ctx) == .fold { folds += 1 }
            return Double(folds) / 200.0
        }
        let rock = foldRate(.conservativeRock)       // omahaCoordination 0.85
        let aggressor = foldRate(.hotAggressor)      // omahaCoordination 0.35
        XCTAssertGreaterThan(rock, aggressor + 0.2, "the coordination-demanding rock folds trash far more (D-063)")
    }

    func testBotOnlyReturnsLegalActions() throws {
        // Drive a few hands; every action the bot yields must be legal in the engine.
        let seats = [OmahaSeat(id: 0, stack: 1000), OmahaSeat(id: 1, stack: 1000), OmahaSeat(id: 2, stack: 1000)]
        var hand = OmahaHand(seats: seats, buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 7)
        let bots = [HeuristicOmahaBot(personality: .eagerNovice, seed: 1, equitySamples: 20),
                    HeuristicOmahaBot(personality: .conservativeRock, seed: 2, equitySamples: 20),
                    HeuristicOmahaBot(personality: .hotAggressor, seed: 3, equitySamples: 20)]
        var guardCount = 0
        while !hand.isComplete, guardCount < 100, let ctx = OmahaBotContext(actingIn: hand) {
            guardCount += 1
            let action = bots[ctx.heroSeatID].decide(ctx)
            XCTAssertNoThrow(try hand.apply(action), "the bot must return a legal action: \(action)")
        }
        XCTAssertTrue(hand.isComplete)
    }

    // MARK: - Additive retro-compatibility (CONVENTIONS §4-bis): Texas/Draw unchanged

    func testOmahaDimsDoNotAffectTexasBot() {
        // Two personalities identical EXCEPT the Omaha dials.
        let base = Personality(name: "x", tightness: 0.5, aggression: 0.5, bluffFrequency: 0.3,
                               riskTolerance: 0.4, positionAwareness: 0.5, rationality: 0.7,
                               tiltReactivity: 0.3, omahaCoordination: 0.0, omahaNuttiness: 0.0)
        let tweaked = Personality(name: "x", tightness: 0.5, aggression: 0.5, bluffFrequency: 0.3,
                                  riskTolerance: 0.4, positionAwareness: 0.5, rationality: 0.7,
                                  tiltReactivity: 0.3, omahaCoordination: 1.0, omahaNuttiness: 1.0)
        var thand = HoldemHand(seats: [Seat(id: 0, stack: 1000), Seat(id: 1, stack: 1000), Seat(id: 2, stack: 1000)],
                               buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 55)
        try? thand.apply(.call); try? thand.apply(.call); try? thand.apply(.check)
        let ctx = BotContext(actingIn: thand)!
        let a = HeuristicBot(personality: base, seed: 9).decide(ctx)
        let b = HeuristicBot(personality: tweaked, seed: 9).decide(ctx)
        XCTAssertEqual(a, b, "the Omaha dials must not change a Texas decision (additive)")
    }

    func testOmahaDimsDoNotAffectDrawBot() {
        let base = Personality(name: "x", tightness: 0.5, aggression: 0.5, bluffFrequency: 0.3,
                               riskTolerance: 0.4, positionAwareness: 0.5, rationality: 0.7,
                               tiltReactivity: 0.3, omahaCoordination: 0.0, omahaNuttiness: 0.0)
        let tweaked = Personality(name: "x", tightness: 0.5, aggression: 0.5, bluffFrequency: 0.3,
                                  riskTolerance: 0.4, positionAwareness: 0.5, rationality: 0.7,
                                  tiltReactivity: 0.3, omahaCoordination: 1.0, omahaNuttiness: 1.0)
        var dhand = FiveCardDrawHand(seats: [DrawSeat(id: 0, stack: 1000), DrawSeat(id: 1, stack: 1000)],
                                     buttonIndex: 0, ante: 5, smallBet: 10, bigBet: 20, seed: 55)
        let ctx = DrawBotContext(actingIn: dhand)!
        let a = HeuristicDrawBot(personality: base, seed: 9).decideAction(ctx)
        let b = HeuristicDrawBot(personality: tweaked, seed: 9).decideAction(ctx)
        XCTAssertEqual(a, b, "the Omaha dials must not change a Draw decision (additive)")
        _ = dhand
    }

    /// The existing presets' NON-Omaha fields are unchanged (guard against accidental
    /// Texas/Draw re-calibration while adding the Omaha dials).
    func testExistingPresetFieldsUnchanged() {
        XCTAssertEqual(Personality.eagerNovice.tightness, 0.20)
        XCTAssertEqual(Personality.eagerNovice.trashFoldTendency, 0.30)
        XCTAssertEqual(Personality.conservativeRock.tightness, 0.90)
        XCTAssertEqual(Personality.conservativeRock.drawDiscipline, 0.90)
        XCTAssertEqual(Personality.hotAggressor.aggression, 0.90)
        XCTAssertEqual(Personality.hotAggressor.pressureResistance, 0.75)
        // The new dials are set for differentiated Omaha play but don't touch the rest.
        XCTAssertEqual(Personality.conservativeRock.omahaNuttiness, 0.85)
        XCTAssertEqual(Personality.hotAggressor.omahaCoordination, 0.35)
    }
}
