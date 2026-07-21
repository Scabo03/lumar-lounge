// EarlyLeaveRetention.swift
// =====================================================================
// What a poker player keeps when they STAND UP EARLY (D-099).
//
// A poker session has a natural end: bust every opponent and you win the
// table. Leaving before that is quitting an unfinished game, so — unlike
// blackjack, where there is no such end and walking away is the normal way to
// stop (D-090) — an early departure forfeits PART of the stack. How much you
// forfeit depends on how well you were doing: dominate the table and you keep
// everything, flee while behind and you keep little.
//
// It is a SESSION economics rule, so it lives in GameWorld beside the House
// Prize (D-079) and the Machiavelli refund (D-075), NOT in an engine. It is
// PURE and casino-agnostic: the amount is a fraction of the stack driven by
// the RATIO of the player's stack to the opponents', so the different stakes of
// the three casinos need no special-casing — a 2× lead is a 2× lead at any
// buy-in. Machiavelli has its own rule and does not use this (D-075).

import Foundation

public enum EarlyLeaveRetention {

    /// The fiches a poker player takes home when they abandon the table before the
    /// session's natural end. `heroStack` is already net of anything committed to
    /// the current pot (that is forfeit regardless, D-086); this decides how much of
    /// what is LEFT comes home.
    ///
    /// - Parameters:
    ///   - heroStack: the player's remaining table fiches.
    ///   - aliveOpponentStacks: the fiches of every opponent still in the game.
    ///   - eliminatedCount: how many opponents the player has already busted.
    public static func retained(heroStack: Int,
                                aliveOpponentStacks: [Int],
                                eliminatedCount: Int) -> Int {
        guard heroStack > 0 else { return 0 }
        let opponentSum = aliveOpponentStacks.reduce(0, +)
        // No live opponents left to measure against — which cannot happen at a real
        // voluntary leave, because busting everyone ENDS the session as a win, but
        // keep the function total: total dominance keeps the whole stack.
        guard opponentSum > 0 else { return heroStack }

        let lead = Double(heroStack) / Double(opponentSum)
        var fraction = fractionForLead(lead)
        // Busting even one opponent is a concrete achievement: the floor is half the
        // stack, whatever the ratio then says.
        if eliminatedCount >= 1 { fraction = max(fraction, 0.50) }
        return Int((Double(heroStack) * fraction).rounded())
    }

    /// The kept fraction as a function of the stack LEAD (hero ÷ live opponents' sum).
    /// The anchors, from the request:
    ///   • lead ≥ 2.0  → 1.00  (stack ≥ double ALL remaining opponents → keep it all)
    ///   • lead = 1.3  → 0.90  (30% ahead → keep 90%)
    ///   • lead = 1.0  → 0.50  (dead even → keep half)
    ///   • lead ≤ 0.5  → 0.25  (well behind → keep a quarter; leaving is fleeing)
    /// Linear between the anchors.
    static func fractionForLead(_ lead: Double) -> Double {
        switch lead {
        case ..<0.5:    return 0.25
        case 0.5..<1.0: return interpolate(lead, 0.5, 1.0, 0.25, 0.50)
        case 1.0..<1.3: return interpolate(lead, 1.0, 1.3, 0.50, 0.90)
        case 1.3..<2.0: return interpolate(lead, 1.3, 2.0, 0.90, 1.00)
        default:        return 1.00
        }
    }

    private static func interpolate(_ x: Double, _ x0: Double, _ x1: Double,
                                    _ y0: Double, _ y1: Double) -> Double {
        y0 + (x - x0) / (x1 - x0) * (y1 - y0)
    }
}
