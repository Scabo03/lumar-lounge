import XCTest
@testable import GameWorld
@testable import GameEngine

/// Characterisation (D-037): the Fast table's bot personalities make VISIBLY more
/// aggressive/looser decisions than the Classic roster in identical spots — facing
/// a bet with a marginal hand, they commit chips (call/bet/raise) far more often
/// than the tight Classic roster, which folds.
final class FastTablePersonalityTests: XCTestCase {

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

    /// Committing chips rather than folding/checking (loose + aggressive).
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

    func testFastRosterCommitsChipsMoreOftenThanClassic() {
        // Marginal hands facing a bet: a tight roster folds, a loose one plays back.
        let contexts = [
            facingBet(hole: Hand(Card(.nine, .hearts), Card(.eight, .hearts)),
                      board: [Card(.two, .spades), Card(.king, .diamonds), Card(.five, .clubs)], toCall: 40),
            facingBet(hole: Hand(Card(.king, .clubs), Card(.ten, .diamonds)), board: [], toCall: 40),
            facingBet(hole: Hand(Card(.six, .spades), Card(.six, .clubs)),
                      board: [Card(.ace, .hearts), Card(.jack, .clubs), Card(.two, .diamonds)], toCall: 60),
        ]
        let classic = commitCount(WorldPersonalities.classic, contexts: contexts, seeds: 40)
        let fast = commitCount(WorldPersonalities.fast, contexts: contexts, seeds: 40)
        XCTAssertGreaterThan(fast, classic,
                             "Fast personalities should commit chips more often (fast=\(fast), classic=\(classic))")
    }
}
