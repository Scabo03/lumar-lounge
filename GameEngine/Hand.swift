// Hand.swift
// =====================================================================
// A player's hand *in progress*: the two hole cards a seat holds during a
// single dealt hand of Texas Hold'em.
//
// This is deliberately DISTINCT from `HandRank` (see D-002 in ../CLAUDE.md):
//   - `Hand`     is player-centric — "what this seat is holding right now".
//   - `HandRank` is evaluation-centric — "how strong five chosen cards are".
// The betting engine deals a `Hand` to each seat; at showdown it combines a
// seat's `Hand` with the board and asks `HandEvaluator` for a `HandRank`.
//
// Foundation only, no knowledge of tables, pots or turns.

import Foundation

/// The two private hole cards held by a seat during a hand of Hold'em.
public struct Hand: Hashable, CustomStringConvertible, Sendable {
    /// Exactly two hole cards.
    public let cards: [Card]

    public init(_ first: Card, _ second: Card) {
        self.cards = [first, second]
    }

    /// - Precondition: `cards` must contain exactly two cards.
    public init(_ cards: [Card]) {
        precondition(cards.count == 2, "A Hold'em hand holds exactly two hole cards.")
        self.cards = cards
    }

    /// Debug form, e.g. "A♠ K♥".
    public var description: String {
        cards.map(\.description).joined(separator: " ")
    }
}
