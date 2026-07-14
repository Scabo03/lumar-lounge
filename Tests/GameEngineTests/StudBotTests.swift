import XCTest
@testable import GameEngine

/// The Stud bot and its redacted context: honest information (sees opponents' UP cards,
/// never their DOWN cards), determinism, board reading, and additive back-compat of the
/// new `studBoardReading` dimension (D-076/D-077).
final class StudBotTests: XCTestCase {

    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    // MARK: - Honest information (D-009)

    func testContextExposesOpponentUpCardsButNeverDownCards() {
        var hand = StudHand(seats: (0..<3).map { StudSeat(id: $0, stack: 3000) },
                            ante: 25, bringIn: 25, bet: 50, seed: 9)
        let ctx = StudBotContext(actingIn: hand)!
        // The hero sees its own down + up cards.
        XCTAssertEqual(ctx.holeCards.count, 2)
        XCTAssertEqual(ctx.upCards.count, 1)
        // Each opponent's UP cards are visible; there is no field carrying their DOWN
        // cards — they are structurally absent from the context type.
        let opponents = ctx.seats.filter { !$0.isHero }
        XCTAssertEqual(opponents.count, 2)
        for opp in opponents { XCTAssertEqual(opp.upCards.count, 1, "opponents' up cards are public") }
        // Cross-check: the union of every up card the bot can see equals the engine's up
        // cards; no down card of any opponent leaks.
        let visibleUp = Set(ctx.seats.flatMap { $0.upCards })
        let engineUp = Set(hand.seats.flatMap { $0.upCards })
        XCTAssertEqual(visibleUp, engineUp)
        let engineOpponentDown = Set(hand.seats.filter { $0.id != ctx.heroSeatID }.flatMap { $0.holeCards })
        XCTAssertTrue(visibleUp.isDisjoint(with: engineOpponentDown), "no opponent down card is visible as an up card")
    }

    func testFoldedOpponentShowsNoUpCards() {
        var hand = StudHand(seats: (0..<3).map { StudSeat(id: $0, stack: 3000) },
                            ante: 25, bringIn: 25, bet: 50, seed: 4)
        // First actor folds.
        try! hand.apply(.fold)
        let ctx = StudBotContext(actingIn: hand)!
        let folded = ctx.seats.first { $0.hasFolded }
        XCTAssertNotNil(folded)
        XCTAssertTrue(folded!.upCards.isEmpty, "a folded seat exposes no up cards")
    }

    // MARK: - Determinism

    func testDeterministicDecision() {
        let bot = HeuristicStudBot(personality: .conservativeRock, seed: 123)
        var hand = StudHand(seats: (0..<3).map { StudSeat(id: $0, stack: 3000) },
                            ante: 25, bringIn: 25, bet: 50, seed: 8)
        let ctx = StudBotContext(actingIn: hand)!
        XCTAssertEqual(bot.decide(ctx), bot.decide(ctx), "same bot + same situation → same action")
    }

    // MARK: - Board reading (D-076)

    /// A sharp board reader folds a marginal hand more often against a THREATENING
    /// opposing board than a bot that ignores the boards.
    func testHighBoardReaderFoldsMoreAgainstAScaryBoard() {
        func makeContext(botSeed: UInt64) -> StudBotContext {
            // Hero: a modest pair of nines showing weak, facing a bet on fifth street.
            let heroHole = [c(.nine, .clubs), c(.nine, .diamonds)]
            let heroUp = [c(.king, .spades), c(.four, .hearts), c(.two, .spades)]
            // Opponent shows a menacing pair of aces (board threat).
            let oppUp = [c(.ace, .hearts), c(.ace, .diamonds), c(.king, .hearts)]
            let legal = StudLegalActions(seatID: 0, canFold: true, canCheck: false, canCall: true,
                                         callAmount: 120, canBet: false, minBetTo: 0, maxBetTo: 0,
                                         canRaise: true, minRaiseTo: 240, maxRaiseTo: 600, canAllIn: true)
            let seats = [
                StudPublicSeat(id: 0, stack: 2000, streetBet: 0, totalBet: 200, upCards: heroUp,
                               hasFolded: false, isAllIn: false, isHero: true),
                StudPublicSeat(id: 1, stack: 2000, streetBet: 120, totalBet: 320, upCards: oppUp,
                               hasFolded: false, isAllIn: false, isHero: false),
            ]
            return StudBotContext(heroSeatID: 0, holeCards: heroHole, upCards: heroUp, street: .fifth,
                                  potSize: 400, currentBet: 120, toCall: 120, heroStack: 2000, bet: 50,
                                  legal: legal, seats: seats, activeOpponents: 1,
                                  aggressionFacedThisStreet: true)
        }

        func foldRate(reading: Double) -> Int {
            let p = Personality(name: "reader", tightness: 0.5, aggression: 0.4, bluffFrequency: 0.1,
                                riskTolerance: 0.4, positionAwareness: 0.5, rationality: 0.8,
                                tiltReactivity: 0.2, studBoardReading: reading)
            var folds = 0
            for seed: UInt64 in 0..<140 {
                let bot = HeuristicStudBot(personality: p, seed: seed, equitySamples: 24)
                if bot.decide(makeContext(botSeed: seed)) == .fold { folds += 1 }
            }
            return folds
        }

        let blind = foldRate(reading: 0.05)
        let sharp = foldRate(reading: 0.95)
        XCTAssertGreaterThan(sharp, blind, "the board reader folds the marginal hand more against a scary board")
    }

    // MARK: - Additive back-compat (CONVENTIONS §1)

    /// Changing ONLY `studBoardReading` never changes a Texas Hold'em decision — no other
    /// game reads the dial.
    func testStudBoardReadingDoesNotAffectTexas() {
        func personality(_ reading: Double) -> Personality {
            Personality(name: "x", tightness: 0.6, aggression: 0.5, bluffFrequency: 0.2,
                        riskTolerance: 0.4, positionAwareness: 0.5, rationality: 0.8,
                        tiltReactivity: 0.2, studBoardReading: reading)
        }
        let a = personality(0.0)
        let b = personality(1.0)

        func play(_ p: Personality) -> [String] {
            let bot = HeuristicBot(personality: p, seed: 77)
            var hand = HoldemHand(seats: (0..<3).map { Seat(id: $0, stack: 1000) },
                                  buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 21)
            var actions: [String] = []
            while !hand.isComplete {
                guard let ctx = BotContext(actingIn: hand) else { break }
                let action = bot.decide(ctx)
                actions.append("\(action)")
                try? hand.apply(action)
            }
            return actions
        }
        XCTAssertEqual(play(a), play(b), "studBoardReading is inert in Texas — identical action sequence")
    }
}
