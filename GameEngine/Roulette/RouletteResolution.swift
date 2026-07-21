// RouletteResolution.swift
// =====================================================================
// Settling a spin (D-101): given the winning pocket and the player's bets, who
// paid, who lost, and — the one house rule with teeth — what the zero returns.
//
// THE ZERO RULE, imposed and non-negotiable (D-101). When zero comes up, the
// SIMPLE even-money outside bets (red/black, even/odd, the two halves) are NOT
// lost but RETURNED IN FULL. This is neither the classic en prison (which jails
// the bet for the next spin) nor la partage (half back): it is immediate full
// return, the form most favourable to the player. Crucially, it means zero
// closes the round CLEAN — no bet state survives into the next spin, so there is
// nothing to carry (which the driver and UI rely on). Inside bets that cover
// zero win normally at their odds.

import Foundation

/// How one bet settled.
public struct RouletteBetResolution: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case won(profit: Int)      // covered the pocket: stake back plus profit
        case lost                  // did not cover: stake gone
        case refundedOnZero        // even-money outside bet, zero came up: stake back, no profit
    }

    public let bet: RouletteBet
    public let amount: Int
    public let outcome: Outcome

    /// Chips coming back to the player from this bet: stake + profit on a win, the
    /// stake on a zero refund, nothing on a loss.
    public var returned: Int {
        switch outcome {
        case let .won(profit): return amount + profit
        case .refundedOnZero:  return amount
        case .lost:            return 0
        }
    }

    public var net: Int { returned - amount }
    public var didWin: Bool { if case .won = outcome { return true } else { return false } }
}

/// The full settlement of one spin.
public struct RouletteRoundResolution: Equatable, Sendable {
    public let winningPocket: Int
    public let color: RouletteColor
    public let results: [RouletteBetResolution]

    public var totalStaked: Int { results.reduce(0) { $0 + $1.amount } }
    public var totalReturned: Int { results.reduce(0) { $0 + $1.returned } }
    public var net: Int { totalReturned - totalStaked }

    /// The bets that paid (for "which of your bets won"), and the money they made.
    public var winningResults: [RouletteBetResolution] { results.filter { $0.didWin } }
    public var totalWon: Int { winningResults.reduce(0) { $0 + $1.returned } }

    /// Whether any simple even-money bet was handed back because zero came up — the
    /// fact the announcement must explain so the player understands why they did not
    /// lose what they expected to (D-101).
    public var zeroRefunded: Bool {
        results.contains { if case .refundedOnZero = $0.outcome { return true } else { return false } }
    }
}

public enum RouletteResolver {

    /// Settles `bets` (bet → staked amount) against `pocket`, applying the zero rule.
    public static func resolve(bets: [RouletteBet: Int], pocket: Int) -> RouletteRoundResolution {
        // A stable order so the resolution is deterministic and the announcement
        // reads the same way each time: by frequency class, then by the numbers.
        let ordered = bets.sorted { a, b in
            if a.key.frequencyRank != b.key.frequencyRank { return a.key.frequencyRank < b.key.frequencyRank }
            if a.key.covered != b.key.covered { return a.key.covered.lexicographicallyPrecedes(b.key.covered) }
            return a.key.kind.rawValue < b.key.kind.rawValue
        }

        let results = ordered.map { bet, amount -> RouletteBetResolution in
            let outcome: RouletteBetResolution.Outcome
            if pocket == 0 && bet.isEvenMoneyOutside {
                outcome = .refundedOnZero
            } else if bet.covered.contains(pocket) {
                outcome = .won(profit: amount * bet.oddsToOne)
            } else {
                outcome = .lost
            }
            return RouletteBetResolution(bet: bet, amount: amount, outcome: outcome)
        }

        return RouletteRoundResolution(winningPocket: pocket,
                                       color: RouletteLayout.color(of: pocket),
                                       results: results)
    }
}
