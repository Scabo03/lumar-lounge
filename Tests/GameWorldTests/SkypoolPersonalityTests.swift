import XCTest
@testable import GameWorld
@testable import GameEngine

/// The three Skypool URBAN personalities (D-066): declared as their own entities,
/// recognisably DIFFERENT from the Riverwood frontier roster, yet ADDITIVE — turning
/// the Omaha levers never changes a Texas/Draw decision (the Riverwood is untouched).
final class SkypoolPersonalityTests: XCTestCase {

    private func facingBet(hole: Hand, board: [Card], toCall: Int) -> BotContext {
        let stack = 1000, bb = 20
        let legal = LegalActions(seatID: 0, canFold: true, canCheck: false, canCall: true, callAmount: toCall,
                                 canBet: false, minBetTo: 0, maxBetTo: 0,
                                 canRaise: true, minRaiseTo: toCall + bb, maxRaiseTo: stack, canAllIn: true)
        return BotContext(heroSeatID: 0, hole: hole, board: board,
                          street: board.isEmpty ? .preflop : .flop, potSize: 100,
                          currentBet: toCall, toCall: toCall, heroStack: stack, bigBlind: bb, legal: legal,
                          seats: [], activeOpponents: 2, lateness: 0.5,
                          aggressionFacedThisStreet: true, emotionalTemperature: 0)
    }

    private func commitsChips(_ action: Action) -> Bool {
        switch action { case .call, .bet, .raise, .allIn: return true; case .fold, .check: return false }
    }

    private func commitCount(_ roster: [Personality], contexts: [BotContext], seeds: Int) -> Int {
        var count = 0
        for personality in roster {
            for seed in 0..<seeds {
                let bot = HeuristicBot(personality: personality, seed: UInt64(seed) * 7 + 3, equitySamples: 40)
                for context in contexts where commitsChips(bot.decide(context)) { count += 1 }
            }
        }
        return count
    }

    // MARK: - Distinct entities (D-066)

    func testUrbanPersonalitiesAreOwnEntitiesNotTheRiverwoodPresets() {
        // Distinct roster from the frontier presets, and from the Riverwood Fast set.
        XCTAssertNotEqual(WorldPersonalities.skypool, WorldPersonalities.classic)
        XCTAssertNotEqual(WorldPersonalities.skypool, WorldPersonalities.fast)
        XCTAssertEqual(WorldPersonalities.skypool.count, 3)
    }

    func testUrbanArchetypesMoveTheExpectedLevers() {
        let urbanNovice = WorldPersonalities.skypool[0]
        let urbanRock = WorldPersonalities.skypool[1]
        let urbanShark = WorldPersonalities.skypool[2]

        // Urban novice: less naive than the frontier boy — more rational, less tilty.
        XCTAssertGreaterThan(urbanNovice.rationality, Personality.eagerNovice.rationality)
        XCTAssertLessThan(urbanNovice.tiltReactivity, Personality.eagerNovice.tiltReactivity)

        // Urban rock: even colder/more professional (higher rationality, lower tilt).
        XCTAssertGreaterThanOrEqual(urbanRock.rationality, Personality.conservativeRock.rationality)
        XCTAssertLessThanOrEqual(urbanRock.tiltReactivity, Personality.conservativeRock.tiltReactivity)

        // Urban shark: even more risk-loving, deep city pockets (higher risk/pressure).
        XCTAssertGreaterThan(urbanShark.riskTolerance, Personality.hotAggressor.riskTolerance)
        XCTAssertGreaterThanOrEqual(urbanShark.pressureResistance, Personality.hotAggressor.pressureResistance)
    }

    // MARK: - Recognisably different behaviour (D-066)

    func testUrbanRosterPlaysRecognisablyDifferentlyFromTheFrontierClassic() {
        let contexts = [
            facingBet(hole: Hand(Card(.nine, .hearts), Card(.eight, .hearts)),
                      board: [Card(.two, .spades), Card(.king, .diamonds), Card(.five, .clubs)], toCall: 40),
            facingBet(hole: Hand(Card(.king, .clubs), Card(.ten, .diamonds)), board: [], toCall: 40),
            facingBet(hole: Hand(Card(.six, .spades), Card(.six, .clubs)),
                      board: [Card(.ace, .hearts), Card(.jack, .clubs), Card(.two, .diamonds)], toCall: 60),
        ]
        let riverwood = commitCount(WorldPersonalities.classic, contexts: contexts, seeds: 40)
        let skypool = commitCount(WorldPersonalities.skypool, contexts: contexts, seeds: 40)
        // The urban roster (looser shark, slightly looser rock, gamier novice) commits
        // chips in marginal spots more often than the tight frontier classic roster.
        XCTAssertGreaterThan(skypool, riverwood,
                             "Skypool roster should play recognisably looser (skypool=\(skypool), riverwood=\(riverwood))")
    }

    // MARK: - Additive: Omaha levers never change Texas decisions (D-063/D-066)

    func testTurningOmahaLeversDoesNotChangeTexasDecisions() {
        let base = WorldPersonalities.skypool[1]   // urban rock
        // Same personality, only the Omaha dials moved to the opposite extreme.
        let twisted = Personality(
            name: base.name, tightness: base.tightness, aggression: base.aggression,
            bluffFrequency: base.bluffFrequency, riskTolerance: base.riskTolerance,
            positionAwareness: base.positionAwareness, rationality: base.rationality,
            tiltReactivity: base.tiltReactivity, pressureResistance: base.pressureResistance,
            trashFoldTendency: base.trashFoldTendency, drawDiscipline: base.drawDiscipline,
            drawBluffiness: base.drawBluffiness, openingDiscipline: base.openingDiscipline,
            omahaCoordination: 1 - base.omahaCoordination, omahaNuttiness: 1 - base.omahaNuttiness)

        let contexts = [
            facingBet(hole: Hand(Card(.ace, .spades), Card(.king, .spades)), board: [], toCall: 40),
            facingBet(hole: Hand(Card(.seven, .hearts), Card(.two, .clubs)),
                      board: [Card(.ace, .diamonds), Card(.jack, .clubs), Card(.four, .spades)], toCall: 50),
        ]
        for context in contexts {
            for seed in 0..<25 {
                let a = HeuristicBot(personality: base, seed: UInt64(seed) &* 11 &+ 1, equitySamples: 30).decide(context)
                let b = HeuristicBot(personality: twisted, seed: UInt64(seed) &* 11 &+ 1, equitySamples: 30).decide(context)
                XCTAssertEqual(a, b, "Omaha levers must not change a Texas decision (seed \(seed))")
            }
        }
    }
}
