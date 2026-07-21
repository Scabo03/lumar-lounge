// RouletteTableRules.swift
// =====================================================================
// The configurable parameters of a roulette table (D-102).
//
// The house rules are identical everywhere and non-negotiable (D-101): a
// European single-zero wheel, standard odds, and the full-return zero rule.
// What distinguishes one table from another is only what it COSTS — the buy-in
// and the per-bet limits — plus the sound of the place, which arrives by data
// from the casino's own palette (D-067). There are no bots at a roulette table.

import Foundation

public struct RouletteTableRules: Equatable, Sendable {

    /// The smallest wager a touch places, and the step of a swipe.
    public let minimumBet: Int
    /// The most that may sit on any single bet.
    public let maximumBet: Int
    /// Chips converted into fiches on sitting down.
    public let buyIn: Int

    public init(minimumBet: Int, maximumBet: Int, buyIn: Int) {
        precondition(minimumBet > 0, "The minimum wager must be positive.")
        precondition(maximumBet >= minimumBet, "The maximum wager cannot be below the minimum.")
        self.minimumBet = minimumBet
        self.maximumBet = maximumBet
        self.buyIn = buyIn
    }

    /// The Riverwood table: a frontier game, wagers a working man can carry — matched
    /// to the house's other tables (Blackjack 20–200, buy-in 1000).
    public static let riverwood = RouletteTableRules(minimumBet: 10,
                                                     maximumBet: 500,
                                                     buyIn: 1000)

    /// The Skypool table: the same game for five times the money, in keeping with the
    /// rest of the house (~5× the Riverwood, as its Blackjack and Texas already are).
    public static let skypool = RouletteTableRules(minimumBet: 50,
                                                   maximumBet: 2500,
                                                   buyIn: 5000)
}
