// DrawStrategy.swift
// =====================================================================
// Pure, testable draw-poker heuristics used by the bot layer: a static
// five-card strength estimate, and the "textbook" discard decision (which cards
// a mathematically disciplined player keeps and which it throws away).
//
// Kept free of any engine or personality state so it can be unit-tested with
// hand-crafted five-card holdings. A personality then MODULATES these outputs
// (discipline, bluffiness) exactly as the Hold'em layer modulates its maths
// (D-010). Foundation only.

import Foundation

enum DrawStrategy {

    /// A static strength for a completed five-card hand, in 0…1: mostly the hand
    /// category, nudged by the top tie-breaker so that, e.g., a pair of kings
    /// ranks above a pair of twos. There is no "draw potential" here — that lives
    /// in the discard decision, not in how strongly a made hand should bet.
    static func strength(_ cards: [Card]) -> Double {
        guard cards.count == 5 else { return 0 }
        let rank = HandEvaluator.evaluate(cards)
        let categoryPart = Double(rank.category.rawValue) / Double(HandCategory.royalFlush.rawValue)
        let topRank = Double(rank.tiebreakers.first ?? 2)
        // A small in-category nudge (0…~0.1) from the leading tie-breaker.
        let nudge = (topRank - 2) / 12 * 0.1
        return Swift.min(1, categoryPart * 0.9 + nudge)
    }

    /// The mathematically correct cards to discard from a five-card holding: keep
    /// the made hand or the strongest draw, throw the rest. This is the baseline
    /// a disciplined bot follows; a loose or deceptive bot deviates from it.
    ///
    /// - Made hands from a straight upward stand pat (discard nothing).
    /// - Trips discard the two odd cards; two pair discards the kicker; a pair
    ///   discards the other three.
    /// - With only a high card, draw one to a four-flush or four-straight if
    ///   present, otherwise keep the single highest card and draw four.
    static func optimalDiscards(from cards: [Card]) -> [Card] {
        guard cards.count == 5 else { return [] }
        let evaluated = HandEvaluator.evaluate(cards)
        let counts: [Rank: [Card]] = Dictionary(grouping: cards, by: { $0.rank })

        switch evaluated.category {
        case .straight, .flush, .fullHouse, .fourOfAKind, .straightFlush, .royalFlush:
            return []                                   // stand pat

        case .threeOfAKind:
            let trips = counts.first { $0.value.count == 3 }!.key
            return cards.filter { $0.rank != trips }     // discard the two odd cards

        case .twoPair:
            let kicker = counts.first { $0.value.count == 1 }!.key
            return cards.filter { $0.rank == kicker }    // discard the lone kicker

        case .pair:
            let pair = counts.first { $0.value.count == 2 }!.key
            return cards.filter { $0.rank != pair }      // keep the pair, draw three

        case .highCard:
            if let flushKeep = fourToFlush(cards) {
                return cards.filter { !flushKeep.contains($0) }   // draw one to the flush
            }
            if let straightKeep = fourToStraight(cards) {
                return cards.filter { !straightKeep.contains($0) } // draw one to the straight
            }
            // Nothing going: keep the single highest card, draw four.
            let highest = cards.max { $0.rank < $1.rank }!
            return cards.filter { $0 != highest }
        }
    }

    // MARK: - Draw detection (high-card holdings only)

    /// Four cards of one suit, if present (the cards to KEEP for a flush draw).
    private static func fourToFlush(_ cards: [Card]) -> [Card]? {
        let bySuit = Dictionary(grouping: cards, by: { $0.suit })
        guard let four = bySuit.first(where: { $0.value.count == 4 })?.value else { return nil }
        return four
    }

    /// Four cards forming a run of four consecutive ranks, if present (the cards
    /// to KEEP for an outside straight draw). Distinct ranks only.
    private static func fourToStraight(_ cards: [Card]) -> [Card]? {
        // One card per rank, sorted ascending; look for four in a row.
        let unique = Dictionary(grouping: cards, by: { $0.rank }).compactMap { $0.value.first }
        let sorted = unique.sorted { $0.rank < $1.rank }
        guard sorted.count >= 4 else { return nil }
        for start in 0...(sorted.count - 4) {
            let window = Array(sorted[start..<start + 4])
            if window.last!.rank.rawValue - window.first!.rank.rawValue == 3 {
                return window
            }
        }
        return nil
    }
}
