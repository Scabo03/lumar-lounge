// StudShowing.swift
// =====================================================================
// Pure helpers for the two Stud-specific ORDERING questions that decide who acts first
// (D-077), kept out of the hand engine so they can be unit-tested in isolation:
//
//   1. The BRING-IN on third street: the lowest up card by rank, ties broken by suit
//      with clubs lowest (`bringInSuitOrder`).
//   2. FIRST TO ACT on fourth–seventh street: the highest poker hand SHOWING in a seat's
//      up cards. Only MADE combinations in the up cards count (a four-flush is NOT a
//      flush showing), so with ≤ 4 up cards the categories are, ascending:
//      high card < pair < two pair < trips < quads. `showingKey` renders a comparable
//      key and `isGreater` compares two keys lexicographically.
//
// These affect only the ORDER of action, never pot correctness. Foundation only.

import Foundation

enum StudShowing {

    /// The bring-in suit ordering — clubs lowest, then diamonds, hearts, spades. The
    /// engine's `Suit` raw order is different (spades first), so bring-in uses this map.
    static func bringInSuitOrder(_ suit: Suit) -> Int {
        switch suit {
        case .clubs:    return 0
        case .diamonds: return 1
        case .hearts:   return 2
        case .spades:   return 3
        }
    }

    /// A lexicographically comparable key for the poker hand SHOWING in `upCards` (up to
    /// four cards). First element is the made-category rank (0 high … 4 quads), then the
    /// ranks that matter, highest first: the quad/trip/pair ranks, then the kickers.
    static func showingKey(_ upCards: [Card]) -> [Int] {
        guard !upCards.isEmpty else { return [0] }
        var counts: [Int: Int] = [:]
        for c in upCards { counts[c.rank.rawValue, default: 0] += 1 }

        // Group ranks by their count, each group sorted by rank descending; groups
        // ordered by count descending then rank descending (standard poker keying).
        let grouped = counts.sorted { a, b in
            a.value != b.value ? a.value > b.value : a.key > b.key
        }
        let maxCount = grouped.first?.value ?? 1
        let pairCount = grouped.filter { $0.value == 2 }.count

        let category: Int
        switch maxCount {
        case 4:  category = 4                       // quads
        case 3:  category = 3                       // trips
        case 2:  category = pairCount >= 2 ? 2 : 1  // two pair / one pair
        default: category = 0                       // high card
        }

        var key = [category]
        key.append(contentsOf: grouped.map { $0.key })
        return key
    }

    /// Whether showing key `a` beats key `b`, comparing lexicographically (a longer key
    /// that shares a prefix beats a shorter one — more matched cards).
    static func isGreater(_ a: [Int], than b: [Int]) -> Bool {
        for i in 0..<Swift.max(a.count, b.count) {
            let x = i < a.count ? a[i] : -1
            let y = i < b.count ? b[i] : -1
            if x != y { return x > y }
        }
        return false
    }
}
