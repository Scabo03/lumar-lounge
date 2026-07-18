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

    /// Default Monte Carlo rollouts for a draw equity estimate. A five-card
    /// showdown is far cheaper to evaluate than a Texas runout, so this can sit
    /// where Texas sits (200) without the bots feeling slow (D-082).
    static let defaultEquitySamples = 160

    /// EQUITY in 0…1: the probability this holding wins the showdown, on the SAME
    /// SCALE the Texas/Omaha/Stud bots use (D-082). This is what the betting bars
    /// (`continueBar`/`callBar`, built from pot odds) are meant to be compared
    /// against — see the note on `strength` below for why the old category score
    /// could not be.
    ///
    /// When `drawToCome` is true (the first betting round) the estimate plays the
    /// exchange forward: the hero draws its textbook cards and so do the opponents,
    /// and the winner is decided on the FIVE CARDS EACH WILL ACTUALLY HOLD. That is
    /// the whole point of the first round — nobody is betting a finished hand, and a
    /// four-flush is worth far more than the "high card" it currently is.
    ///
    /// Honest by construction: opponents are unknown, hence drawn uniformly (D-011).
    /// Deterministic given `rng`.
    static func equity(cards: [Card], opponents: Int, drawToCome: Bool,
                       samples: Int = defaultEquitySamples,
                       using rng: inout SeededGenerator) -> Double {
        guard cards.count == 5, opponents >= 1, samples > 0 else { return strength(cards) }
        let known = Set(cards)
        var pool = Deck().cards.filter { !known.contains($0) }
        // Worst case per sample: hero's 4 replacements + 5 cards each opponent + 4
        // replacements each.
        let needed = (drawToCome ? 4 : 0) + opponents * (drawToCome ? 9 : 5)
        guard pool.count >= needed else { return strength(cards) }

        var wins = 0.0
        for _ in 0..<samples {
            // Partial Fisher–Yates: sample `needed` distinct cards from the pool.
            let count = pool.count
            for i in 0..<needed {
                let j = i + Int(rng.next() % UInt64(count - i))
                pool.swapAt(i, j)
            }
            var index = 0
            func take(_ n: Int) -> [Card] {
                defer { index += n }
                return Array(pool[index..<(index + n)])
            }

            /// Plays the textbook exchange forward for a five-card holding.
            func afterDraw(_ hand: [Card]) -> [Card] {
                guard drawToCome else { return hand }
                let discards = Set(optimalDiscards(from: hand))
                guard !discards.isEmpty else { return hand }
                return hand.filter { !discards.contains($0) } + take(discards.count)
            }

            let heroRank = HandEvaluator.evaluate(afterDraw(cards))

            var bestOpp: HandRank?
            var bestOppCount = 0
            for _ in 0..<opponents {
                let oppRank = HandEvaluator.evaluate(afterDraw(take(5)))
                if bestOpp == nil || oppRank > bestOpp! {
                    bestOpp = oppRank
                    bestOppCount = 1
                } else if oppRank == bestOpp! {
                    bestOppCount += 1
                }
            }

            if bestOpp == nil || heroRank > bestOpp! {
                wins += 1
            } else if heroRank == bestOpp! {
                wins += 1.0 / Double(bestOppCount + 1)   // split among the tied
            }
        }
        return wins / Double(samples)
    }

    /// A static CATEGORY score for a completed five-card hand, in 0…1: mostly the
    /// hand category, nudged by the top tie-breaker so that, e.g., a pair of kings
    /// ranks above a pair of twos.
    ///
    /// ⚠️ This is an ORDINAL RANKING, not an equity (D-082): a pair maxes out at
    /// 0.20 and two pair at 0.30, whereas a pair of aces WINS about 65% of the time.
    /// It must never be compared against a pot-odds bar — that mismatch is exactly
    /// what made every Draw bot fold everything below trips before the exchange. Use
    /// `equity(cards:opponents:drawToCome:…)` for any betting decision; this stays
    /// only for ordering holdings against each other.
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

    /// Whether a five-card holding is clearly weak BEFORE the draw (D-048): no
    /// pair and no real draw — i.e. the textbook play is to throw four cards away.
    /// `optimalDiscards` returns four cards only for exactly this case (a made hand
    /// keeps ≥2; a four-flush/four-straight keeps four), so it is the clean test.
    static func isPreDrawGarbage(_ cards: [Card]) -> Bool {
        optimalDiscards(from: cards).count == 4
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
