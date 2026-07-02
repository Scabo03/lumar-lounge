// Card.swift
// =====================================================================
// Representation of a single playing card: its rank and its suit.
//
// Pure value types, Foundation only. Nothing here knows about players,
// tables, or UI — this is the atomic building block of the rules engine.

import Foundation

/// The rank (value) of a card.
///
/// Raw values follow the "ace high" convention (Ace == 14) so that ranks
/// are naturally `Comparable` by their raw value (a King is greater than a
/// Jack). The special case of the ace playing low (value 1 in the A-2-3-4-5
/// "wheel" straight) is handled locally inside the hand evaluator, not by
/// changing this raw value.
public enum Rank: Int, CaseIterable, Comparable, Hashable, CustomStringConvertible, Sendable {
    case two = 2, three, four, five, six, seven, eight, nine, ten
    case jack, queen, king, ace

    public static func < (lhs: Rank, rhs: Rank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Short, human-readable form for debugging: "2", "10", "J", "Q", "K", "A".
    public var description: String {
        switch self {
        case .two:   return "2"
        case .three: return "3"
        case .four:  return "4"
        case .five:  return "5"
        case .six:   return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine:  return "9"
        case .ten:   return "10"
        case .jack:  return "J"
        case .queen: return "Q"
        case .king:  return "K"
        case .ace:   return "A"
        }
    }
}

/// The suit (seed) of a card.
///
/// `CaseIterable` order is fixed and used to build a deck deterministically.
public enum Suit: Int, CaseIterable, Hashable, CustomStringConvertible, Sendable {
    case spades, hearts, diamonds, clubs

    /// Unicode pip symbol, for debug printing: "♠", "♥", "♦", "♣".
    public var description: String {
        switch self {
        case .spades:   return "♠"
        case .hearts:   return "♥"
        case .diamonds: return "♦"
        case .clubs:    return "♣"
        }
    }
}

/// A single playing card, uniquely identified by its `rank` and `suit`.
///
/// Cards are `Comparable` by rank only (suit does not break ties in poker),
/// so `Card(.king, .spades) > Card(.jack, .hearts)` is `true`. Two cards with
/// the same rank but different suit compare as equal under `<`, while still
/// being distinct values under `Equatable`.
public struct Card: Hashable, Comparable, CustomStringConvertible, Sendable {
    public let rank: Rank
    public let suit: Suit

    public init(_ rank: Rank, _ suit: Suit) {
        self.rank = rank
        self.suit = suit
    }

    /// Ordering by rank only — suits are considered of equal value in poker.
    public static func < (lhs: Card, rhs: Card) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Debug form combining rank and suit, e.g. "A♠", "K♥", "10♣", "2♦".
    public var description: String {
        "\(rank)\(suit)"
    }
}
