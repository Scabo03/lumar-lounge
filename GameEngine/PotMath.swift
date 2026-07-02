// PotMath.swift
// =====================================================================
// Pure functions for the two chip-arithmetic problems of a poker hand:
//   1. splitting the total wagered into a main pot and side pots when seats
//      are all-in for different amounts, and
//   2. dividing a pot among tied winners, including the indivisible odd chip.
//
// Kept free of any engine state so they can be unit-tested in isolation with
// hand-crafted inputs (the RNG-driven engine can't easily produce ties or
// exact side-pot shapes on demand). Foundation only.

import Foundation

/// Chip arithmetic for pots. Internal: exposed to the test target via
/// `@testable import`, not part of the public API.
enum PotMath {

    /// One seat's contribution to the hand.
    struct Contribution: Equatable {
        let id: Int
        /// Total chips this seat put in across the whole hand.
        let amount: Int
        /// Whether the seat folded (still contributes chips, cannot win).
        let folded: Bool

        init(id: Int, amount: Int, folded: Bool) {
            self.id = id
            self.amount = amount
            self.folded = folded
        }
    }

    /// Splits the total contributions into a main pot plus side pots.
    ///
    /// Each distinct contribution level becomes a pot layer: everyone who put in
    /// at least that level contributes `(level - previousLevel)` chips to it, and
    /// the non-folded contributors at that level are eligible to win it. An
    /// uncalled overbet naturally comes back as a top layer with a single
    /// eligible seat (that seat simply wins its own chips back).
    ///
    /// - Returns: pots ordered from main pot (lowest level) to last side pot.
    static func sidePots(from contributions: [Contribution]) -> [Pot] {
        let levels = Set(contributions.map(\.amount)).filter { $0 > 0 }.sorted()
        var pots: [Pot] = []
        var previousLevel = 0
        for level in levels {
            let atOrAbove = contributions.filter { $0.amount >= level }
            let amount = (level - previousLevel) * atOrAbove.count
            let eligible = atOrAbove.filter { !$0.folded }.map(\.id).sorted()
            if amount > 0 {
                pots.append(Pot(amount: amount, eligibleSeatIDs: eligible))
            }
            previousLevel = level
        }
        return pots
    }

    /// Divides `amount` among winners, giving each an equal share and handing
    /// out any indivisible remainder chips one at a time in the given priority
    /// order.
    ///
    /// The engine passes winners ordered clockwise from the seat left of the
    /// button, so the odd chip goes to the first such seat (the standard
    /// house rule — see D-004 in ../CLAUDE.md).
    ///
    /// - Parameter ordered: winners in the order that should receive leftover
    ///   chips first.
    static func distribute(_ amount: Int, toWinnersInPriorityOrder ordered: [Int]) -> [Int: Int] {
        guard !ordered.isEmpty else { return [:] }
        let base = amount / ordered.count
        var remainder = amount % ordered.count
        var payout: [Int: Int] = [:]
        for id in ordered {
            payout[id] = base + (remainder > 0 ? 1 : 0)
            if remainder > 0 { remainder -= 1 }
        }
        return payout
    }
}
