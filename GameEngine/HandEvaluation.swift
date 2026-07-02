// HandEvaluation.swift
// =====================================================================
// Poker hand evaluation: given five or more cards, find the best possible
// five-card hand, classify it, and compare it against other evaluated hands.
//
// Foundation only. No knowledge of players, pots, or Texas Hold'em rules
// beyond the mechanics of what makes a hand — this stays purely combinatorial.

import Foundation

/// The ten standard poker hand categories, in ascending order of value.
///
/// Being `Comparable` by raw value means any flush beats any straight, any
/// straight beats any three-of-a-kind, and so on, directly via `<`.
public enum HandCategory: Int, Comparable, CaseIterable, CustomStringConvertible, Sendable {
    case highCard = 0
    case pair
    case twoPair
    case threeOfAKind
    case straight
    case flush
    case fullHouse
    case fourOfAKind
    case straightFlush
    case royalFlush

    public static func < (lhs: HandCategory, rhs: HandCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// English label, for debug output only (never shown to the player).
    public var description: String {
        switch self {
        case .highCard:      return "High Card"
        case .pair:          return "Pair"
        case .twoPair:       return "Two Pair"
        case .threeOfAKind:  return "Three of a Kind"
        case .straight:      return "Straight"
        case .flush:         return "Flush"
        case .fullHouse:     return "Full House"
        case .fourOfAKind:   return "Four of a Kind"
        case .straightFlush: return "Straight Flush"
        case .royalFlush:    return "Royal Flush"
        }
    }
}

/// The result of evaluating a hand: its category, the tie-breaking values that
/// order two hands of the same category, and the exact five cards that form it.
///
/// `tiebreakers` is an ordered list of rank values (2...14). It is compared
/// lexicographically after the category, encoding both the "main combination"
/// ranks and the kickers. For example a pair of Aces with a King kicker yields
/// `[14, 14 (implied), kicker...]` in the form `[pairRank, k1, k2, k3]`.
public struct HandRank: Comparable, CustomStringConvertible, Sendable {
    public let category: HandCategory
    public let tiebreakers: [Int]
    public let cards: [Card]

    public init(category: HandCategory, tiebreakers: [Int], cards: [Card]) {
        self.category = category
        self.tiebreakers = tiebreakers
        self.cards = cards
    }

    /// Category first; on a tie, the tie-breaker values in order. Two hands are
    /// equal (a split pot) only when both category and all tie-breakers match.
    public static func < (lhs: HandRank, rhs: HandRank) -> Bool {
        if lhs.category != rhs.category {
            return lhs.category < rhs.category
        }
        // Same category ⇒ same tie-breaker arity; compare element by element.
        for (l, r) in zip(lhs.tiebreakers, rhs.tiebreakers) where l != r {
            return l < r
        }
        return false
    }

    /// Two hands are equal — an absolute tie / split pot — when neither beats
    /// the other.
    public static func == (lhs: HandRank, rhs: HandRank) -> Bool {
        lhs.category == rhs.category && lhs.tiebreakers == rhs.tiebreakers
    }

    public var description: String {
        "\(category) \(cards.map(\.description).joined(separator: " "))"
    }
}

/// Evaluates poker hands from a set of cards.
public enum HandEvaluator {

    /// Evaluates the best five-card hand out of the given cards.
    ///
    /// Accepts five or more cards (e.g. the seven of Texas Hold'em: two hole
    /// cards plus five board cards) and returns the strongest five-card
    /// `HandRank` that can be formed from them.
    ///
    /// - Precondition: at least five cards must be supplied.
    public static func evaluate(_ cards: [Card]) -> HandRank {
        precondition(cards.count >= 5, "Hand evaluation requires at least five cards.")

        if cards.count == 5 {
            return evaluateFive(cards)
        }

        // More than five cards: pick the best of every 5-card combination.
        var best: HandRank?
        for combo in combinations(of: cards, choose: 5) {
            let rank = evaluateFive(combo)
            if best == nil || rank > best! {
                best = rank
            }
        }
        // Safe: with >= 5 cards there is always at least one combination.
        return best!
    }

    /// Compares two card sets and reports the outcome for the first one.
    public enum Comparison: Sendable { case win, lose, tie }

    /// Convenience: evaluates both sides and reports how `lhs` fares vs `rhs`.
    public static func compare(_ lhs: [Card], _ rhs: [Card]) -> Comparison {
        let a = evaluate(lhs)
        let b = evaluate(rhs)
        if a > b { return .win }
        if a < b { return .lose }
        return .tie
    }

    // MARK: - Exactly five cards

    /// Classifies exactly five cards into a `HandRank`.
    private static func evaluateFive(_ cards: [Card]) -> HandRank {
        precondition(cards.count == 5)

        let ranks = cards.map { $0.rank.rawValue }
        let isFlush = Set(cards.map(\.suit)).count == 1

        // Straight detection, including the A-2-3-4-5 "wheel" (Ace plays low).
        let straightHigh = straightHighCard(ranks)
        let isStraight = straightHigh != nil

        // Group ranks by how many times each appears, then order the distinct
        // ranks by (count desc, rank desc). This ordering is exactly the
        // tie-breaker sequence for pairs, trips, quads, full houses, flushes
        // and high cards (main combination ranks first, kickers after).
        var counts: [Int: Int] = [:]
        for r in ranks { counts[r, default: 0] += 1 }
        let orderedRanks = counts.keys.sorted { a, b in
            if counts[a]! != counts[b]! { return counts[a]! > counts[b]! }
            return a > b
        }
        let countPattern = orderedRanks.map { counts[$0]! } // e.g. [3,2] = full house
        let tiebreakByCount = orderedRanks

        // Order the five cards themselves to match the tie-breaker ordering,
        // so `HandRank.cards` reads as the meaningful five (combo first).
        let orderedCards = cards.sorted { lhs, rhs in
            let lc = counts[lhs.rank.rawValue]!
            let rc = counts[rhs.rank.rawValue]!
            if lc != rc { return lc > rc }
            return lhs.rank.rawValue > rhs.rank.rawValue
        }

        // Classify from strongest to weakest.
        if isStraight && isFlush {
            let category: HandCategory = (straightHigh! == Rank.ace.rawValue) ? .royalFlush : .straightFlush
            return HandRank(category: category, tiebreakers: [straightHigh!], cards: orderedCards)
        }
        if countPattern == [4, 1] {
            return HandRank(category: .fourOfAKind, tiebreakers: tiebreakByCount, cards: orderedCards)
        }
        if countPattern == [3, 2] {
            return HandRank(category: .fullHouse, tiebreakers: tiebreakByCount, cards: orderedCards)
        }
        if isFlush {
            return HandRank(category: .flush, tiebreakers: ranks.sorted(by: >), cards: orderedCards)
        }
        if isStraight {
            return HandRank(category: .straight, tiebreakers: [straightHigh!], cards: orderedCards)
        }
        if countPattern == [3, 1, 1] {
            return HandRank(category: .threeOfAKind, tiebreakers: tiebreakByCount, cards: orderedCards)
        }
        if countPattern == [2, 2, 1] {
            return HandRank(category: .twoPair, tiebreakers: tiebreakByCount, cards: orderedCards)
        }
        if countPattern == [2, 1, 1, 1] {
            return HandRank(category: .pair, tiebreakers: tiebreakByCount, cards: orderedCards)
        }
        return HandRank(category: .highCard, tiebreakers: ranks.sorted(by: >), cards: orderedCards)
    }

    /// Returns the high-card value of a straight formed by these five rank
    /// values, or `nil` if they are not consecutive.
    ///
    /// Handles the wheel (A-2-3-4-5): the ace, normally 14, is treated as 1 so
    /// the straight is recognised with a high card of 5.
    private static func straightHighCard(_ ranks: [Int]) -> Int? {
        let unique = Set(ranks)
        guard unique.count == 5 else { return nil } // pairs can't form a straight

        let sorted = unique.sorted()
        if sorted.last! - sorted.first! == 4 {
            return sorted.last! // normal consecutive run
        }

        // Wheel: A(14),2,3,4,5 — ace plays low, high card is the 5.
        if unique == [14, 2, 3, 4, 5] {
            return 5
        }
        return nil
    }

    /// All combinations of `choose` elements from `array`, order-independent.
    private static func combinations<T>(of array: [T], choose k: Int) -> [[T]] {
        guard k > 0 else { return [[]] }
        guard array.count >= k else { return [] }
        if array.count == k { return [array] }

        var result: [[T]] = []
        let first = array[0]
        let rest = Array(array.dropFirst())
        // Combinations that include the first element...
        for tail in combinations(of: rest, choose: k - 1) {
            result.append([first] + tail)
        }
        // ...and those that don't.
        result.append(contentsOf: combinations(of: rest, choose: k))
        return result
    }
}
