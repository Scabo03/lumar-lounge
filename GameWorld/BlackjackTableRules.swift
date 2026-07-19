// BlackjackTableRules.swift
// =====================================================================
// The configurable parameters of a blackjack table.
//
// The RULES of the house are identical everywhere (D-090): the dealer stands
// on all seventeens, a natural pays three to two, doubling, splitting and
// surrender are on, and insurance does not exist. What distinguishes one
// table from another is only what it COSTS — the buy-in and the betting
// limits — plus the sound of the place, which arrives by data from the
// casino's own palette (D-067).
//
// There are no personalities here: a blackjack table has no bots.

import Foundation
import GameEngine

public struct BlackjackTableRules: Equatable, Sendable {

    /// The smallest legal wager. Kept EVEN so that three-to-two on a natural
    /// and half-back on a surrender are always exact in whole chips.
    public let minimumBet: Int

    /// The largest legal wager.
    public let maximumBet: Int

    /// Chips converted into fiches on sitting down.
    public let buyIn: Int

    /// The house rules, always `.standard`.
    public let rules: BlackjackRules

    public init(minimumBet: Int, maximumBet: Int, buyIn: Int, rules: BlackjackRules = .standard) {
        precondition(minimumBet > 0 && minimumBet % 2 == 0,
                     "The minimum wager must be positive and even so payouts are exact.")
        precondition(maximumBet >= minimumBet, "The maximum wager cannot be below the minimum.")
        self.minimumBet = minimumBet
        self.maximumBet = maximumBet
        self.buyIn = buyIn
        self.rules = rules
    }

    /// The Riverwood table: a frontier game, wagers a working man can carry.
    /// Buy-in matched to the house's Texas tables.
    public static let riverwood = BlackjackTableRules(minimumBet: 20,
                                                      maximumBet: 200,
                                                      buyIn: 1000)

    /// The Skypool table: the same game for five times the money, in keeping
    /// with the rest of the house (Texas 5000–6000, Omaha 10000).
    public static let skypool = BlackjackTableRules(minimumBet: 100,
                                                    maximumBet: 1000,
                                                    buyIn: 5000)
}
