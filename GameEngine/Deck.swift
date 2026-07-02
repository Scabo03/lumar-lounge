// Deck.swift
// =====================================================================
// A deck of 52 playing cards, with deterministic construction, a
// reproducible (seedable) shuffle, and top-of-deck drawing.
//
// Foundation only. The seedable shuffle exists so that tests — and any
// future replay/debug feature — can reproduce the exact same ordering.

import Foundation

/// A small, deterministic pseudo-random generator (SplitMix64).
///
/// Conforming to `RandomNumberGenerator` lets us feed it straight into the
/// standard-library `shuffle(using:)`, so the shuffle is fully reproducible
/// from a seed without pulling in any dependency beyond Foundation.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// An ordered collection of cards that can be shuffled and drawn from.
public struct Deck: Sendable {
    /// Remaining cards. The "top" of the deck (next to be drawn) is `first`.
    public private(set) var cards: [Card]

    /// Builds a full, ordered 52-card deck: for every suit, every rank,
    /// in a fixed deterministic order.
    public init() {
        var cards: [Card] = []
        cards.reserveCapacity(52)
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                cards.append(Card(rank, suit))
            }
        }
        self.cards = cards
    }

    /// Number of cards still in the deck.
    public var count: Int { cards.count }

    /// Whether the deck has no cards left.
    public var isEmpty: Bool { cards.isEmpty }

    /// Shuffles the deck in place.
    ///
    /// - Parameter seed: When provided, the shuffle is deterministic and
    ///   reproducible — the same seed always yields the same ordering. When
    ///   `nil`, the system's secure random generator is used instead.
    public mutating func shuffle(seed: UInt64? = nil) {
        if let seed {
            var generator = SeededGenerator(seed: seed)
            cards.shuffle(using: &generator)
        } else {
            cards.shuffle()
        }
    }

    /// Removes and returns the top card of the deck.
    ///
    /// - Returns: The drawn card, or `nil` if the deck is empty (drawing from
    ///   an empty deck fails gracefully rather than trapping).
    public mutating func draw() -> Card? {
        cards.isEmpty ? nil : cards.removeFirst()
    }
}
