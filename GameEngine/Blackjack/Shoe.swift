// Shoe.swift
// =====================================================================
// The multi-deck card supply of a blackjack table.
//
// The shared `Deck` is exactly 52 cards and is rebuilt per hand — right for
// poker, wrong for blackjack, where the shoe PERSISTS across rounds and its
// depletion is part of the game. So blackjack owns this type (it is a rule
// of blackjack, not a foundational primitive), built from the foundational
// `Card`/`Rank`/`Suit` only.
//
// Determinism: the shoe carries its own seeded generator, so a shoe created
// with a given seed produces the same sequence of cards across an entire
// session, reshuffles included.

import Foundation

/// A persistent multi-deck card supply with a cut card.
public struct Shoe: Sendable {

    /// How many 52-card decks make up the shoe.
    public let deckCount: Int

    /// The fraction of the shoe dealt before the cut card is reached
    /// (0.75 == reshuffle once three quarters have been dealt).
    public let penetration: Double

    /// Cards still to be dealt; the next card is `first`.
    public private(set) var cards: [Card]

    /// How many shuffles this shoe has been through — surfaced so a session
    /// can narrate "the dealer shuffles" without inspecting card counts.
    public private(set) var shuffleCount: Int

    private var generator: SeededGenerator

    /// The full size of the shoe when freshly built.
    public var capacity: Int { deckCount * 52 }

    public init(deckCount: Int = 6, penetration: Double = 0.75, seed: UInt64) {
        precondition(deckCount >= 1, "A shoe needs at least one deck.")
        precondition(penetration > 0 && penetration < 1, "Penetration must be strictly between 0 and 1.")
        self.deckCount = deckCount
        self.penetration = penetration
        self.generator = SeededGenerator(seed: seed)
        self.cards = []
        self.shuffleCount = 0
        reshuffle()
    }

    /// A shoe with a KNOWN ordering, for tests that need a specific deal.
    ///
    /// Internal on purpose: the frontier cases of blackjack (soft seventeen,
    /// split aces, a natural against a natural) are not reachable by shuffling
    /// and waiting, so the tests stack the shoe instead. Production always goes
    /// through the seeded initialiser.
    init(stacked: [Card], deckCount: Int = 6, penetration: Double = 0.75) {
        self.deckCount = deckCount
        self.penetration = penetration
        self.generator = SeededGenerator(seed: 0)
        self.cards = stacked
        self.shuffleCount = 1
    }

    /// Cards remaining.
    public var count: Int { cards.count }

    /// Whether the cut card has been reached and the shoe should be reshuffled
    /// before the next round.
    ///
    /// This is checked BETWEEN rounds, never mid-round: a round that started
    /// on a thin shoe finishes on it (`draw()` refills only as a last-resort
    /// guarantee), so no round is ever dealt from two different shuffles in a
    /// way the player could not follow.
    public var needsShuffle: Bool {
        Double(capacity - count) >= Double(capacity) * penetration
    }

    /// Rebuilds the shoe to full and shuffles it.
    public mutating func reshuffle() {
        var fresh: [Card] = []
        fresh.reserveCapacity(capacity)
        for _ in 0 ..< deckCount {
            for suit in Suit.allCases {
                for rank in Rank.allCases {
                    fresh.append(Card(rank, suit))
                }
            }
        }
        fresh.shuffle(using: &generator)
        cards = fresh
        shuffleCount += 1
    }

    /// Draws the next card.
    ///
    /// Total by construction: an exhausted shoe reshuffles itself rather than
    /// returning nil, so no round can ever stall for want of a card. With six
    /// decks and a cut card at three quarters this never fires in practice —
    /// it exists so the round state machine has no failure branch to model.
    public mutating func draw() -> Card {
        if cards.isEmpty { reshuffle() }
        return cards.removeFirst()
    }
}
