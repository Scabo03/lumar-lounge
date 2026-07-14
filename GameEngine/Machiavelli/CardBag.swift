// CardBag.swift
// =====================================================================
// A tiny multiset ("bag") of cards, used by the Machiavelli turn model and bot
// search to reason about card CONSERVATION with two decks in play (identical cards
// can appear twice). Kept internal — an implementation detail of this engine.
//
// Foundation only.

import Foundation

/// A multiset of cards: how many copies of each distinct card are present.
struct CardBag: Equatable {
    private(set) var counts: [Card: Int]

    init(_ cards: [Card] = []) {
        var c: [Card: Int] = [:]
        for card in cards { c[card, default: 0] += 1 }
        counts = c
    }

    var isEmpty: Bool { counts.isEmpty }
    var total: Int { counts.values.reduce(0, +) }

    func count(_ card: Card) -> Int { counts[card] ?? 0 }

    /// Every card, expanded with multiplicity, in a canonical (deterministic) order.
    var cards: [Card] {
        counts.keys
            .sorted { ($0.rank.rawValue, $0.suit.rawValue) < ($1.rank.rawValue, $1.suit.rawValue) }
            .flatMap { Array(repeating: $0, count: counts[$0]!) }
    }

    mutating func add(_ card: Card, _ n: Int = 1) { counts[card, default: 0] += n }

    mutating func remove(_ card: Card, _ n: Int = 1) {
        let left = (counts[card] ?? 0) - n
        if left > 0 { counts[card] = left } else { counts[card] = nil }
    }

    /// Whether this bag contains `other` (every card with at least its multiplicity).
    func contains(_ other: CardBag) -> Bool {
        other.counts.allSatisfy { count($0.key) >= $0.value }
    }

    /// `self` minus `other`, or `nil` if `other` is not fully contained (would go
    /// negative). Used for conservation checks (D-070).
    func subtracting(_ other: CardBag) -> CardBag? {
        var result = self
        for (card, n) in other.counts {
            let left = result.count(card) - n
            if left < 0 { return nil }
            if left > 0 { result.counts[card] = left } else { result.counts[card] = nil }
        }
        return result
    }
}
