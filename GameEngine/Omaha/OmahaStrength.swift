// OmahaStrength.swift
// =====================================================================
// Estimating how good an Omaha holding is, from a seat's HONEST point of view: its
// own four cards plus whatever community cards are public. Never peeks at opponents'
// cards.
//
//   - Preflop: a fast heuristic over the FOUR cards. Omaha value is coordination,
//     not raw high-card strength: pairs that can make top sets, suitedness for the
//     NUT flush, and connectedness for wraps — dangling/duplicated cards are worth
//     little. This is why the Texas preflop heuristic is useless here (D-063).
//   - Postflop: a seeded Monte Carlo equity estimate using the CONSTRAINED evaluator
//     (`HandEvaluator.evaluateOmaha`, exactly two hole + three board). Opponents get
//     four random cards each; the board is completed; we count how often we win.
//     Deterministic given the RNG, honest (opponents uniformly random, D-011).
//
// COST NOTE (D-063): the constrained evaluator does 6×10 = 60 five-card evaluations
// per player at the river, ~3× a Texas seven-card evaluation (C(7,5)=21). So an Omaha
// sample costs ~3× a Texas sample; to keep the bots as snappy as Texas we run ~⅓ the
// samples (see `HeuristicOmahaBot.defaultEquitySamples`). Measured numbers are in the
// session summary.
//
// Foundation only.

import Foundation

enum OmahaStrength {

    /// Preflop strength in 0…1 over the four hole cards. Rewards high cards, high
    /// pairs (set potential), suitedness (nut-flush potential when an ace is suited),
    /// double-suited holdings, and connectedness (rundowns/wraps); penalises trips or
    /// quads in hand (dead cards) and monotone suits.
    static func preflop(_ hole: [Card]) -> Double {
        guard hole.count == 4 else { return 0 }
        let ranks = hole.map { $0.rank.rawValue }.sorted(by: >)

        // High-card component (top two cards matter most).
        func hc(_ r: Int) -> Double {
            switch r {
            case 14: return 1.00; case 13: return 0.85; case 12: return 0.72
            case 11: return 0.62; case 10: return 0.52
            default:  return Double(r - 2) / 12.0 * 0.45
            }
        }
        let highScore = hc(ranks[0]) + hc(ranks[1]) + 0.5 * hc(ranks[2]) + 0.3 * hc(ranks[3])

        // Pair component: pairs that can flop a set; high pairs best. Trips/quads are
        // dead cards (a big penalty — AAA♦ is far weaker than AA + two live cards).
        var counts: [Int: Int] = [:]
        for r in ranks { counts[r, default: 0] += 1 }
        let pairRanks = counts.filter { $0.value == 2 }.keys.sorted(by: >)
        let hasTripsOrMore = counts.values.contains { $0 >= 3 }
        var pairScore = 0.0
        for p in pairRanks { pairScore += (p >= 10 ? 0.9 : 0.5) * (p >= 13 ? 1.1 : 1.0) }
        if pairRanks.count == 2 { pairScore *= 1.1 }   // two pairs = double set potential
        if hasTripsOrMore { pairScore *= 0.35 }

        // Suit component: suited pairs (flush potential), premium if an ace is suited
        // (the nut flush), bonus for double-suited, penalty for a tripled/monotone suit.
        var suitCounts: [Suit: Int] = [:]
        for c in hole { suitCounts[c.suit, default: 0] += 1 }
        let suitedGroups = suitCounts.values.filter { $0 >= 2 }
        var suitScore = 0.0
        for g in suitedGroups { suitScore += 0.5 + Double(g - 2) * 0.1 }
        for aceSuit in Set(hole.filter { $0.rank == .ace }.map(\.suit)) where (suitCounts[aceSuit] ?? 0) >= 2 {
            suitScore += 0.4                            // nut-flush potential
        }
        if suitedGroups.count >= 2 { suitScore += 0.3 } // double-suited
        if suitCounts.values.contains(where: { $0 >= 3 }) { suitScore *= 0.6 }

        // Connectedness: four cards in a tight span make big wraps.
        let uniqueDesc = Array(Set(ranks)).sorted(by: >)
        var connScore = 0.0
        if uniqueDesc.count == 4 {
            let span = uniqueDesc.first! - uniqueDesc.last!
            if span <= 3 { connScore = 0.9 } else if span <= 5 { connScore = 0.6 } else if span <= 8 { connScore = 0.3 }
        } else if uniqueDesc.count == 3 {
            connScore = 0.2
        }

        let raw = highScore * 0.9 + pairScore * 0.7 + suitScore * 0.8 + connScore * 0.8
        // raw ≈ 0.3 (rainbow disconnected trash) … ≈ 4.5 (AA-KK double-suited). Normalise.
        return (raw / 4.5).clamped01
    }

    /// Monte Carlo equity in 0…1 against `opponents` unknown four-card hands, using
    /// the constrained (2+3) evaluator. Deterministic given the RNG.
    static func equity(hole: [Card], board: [Card], opponents: Int, samples: Int,
                       using rng: inout SeededGenerator) -> Double {
        let known = Set(hole + board)
        var pool = Deck().cards.filter { !known.contains($0) }
        let needCommunity = 5 - board.count
        let needed = opponents * 4 + needCommunity     // four cards per Omaha opponent
        guard opponents >= 1, needCommunity >= 0, board.count >= 3, pool.count >= needed, samples > 0 else {
            return made(hole: hole, board: board)
        }

        var wins = 0.0
        for _ in 0..<samples {
            // Partial Fisher–Yates: sample `needed` distinct cards from the pool.
            let count = pool.count
            for i in 0..<needed {
                let j = i + Int(rng.next() % UInt64(count - i))
                pool.swapAt(i, j)
            }
            let community = Array(pool[0..<needCommunity])
            let fullBoard = board + community          // exactly five
            let heroRank = HandEvaluator.evaluateOmaha(hole: hole, board: fullBoard)

            var bestOpp: HandRank?
            var bestOppCount = 0
            var index = needCommunity
            for _ in 0..<opponents {
                let oppHole = Array(pool[index..<index + 4])
                index += 4
                let oppRank = HandEvaluator.evaluateOmaha(hole: oppHole, board: fullBoard)
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
                wins += 1.0 / Double(bestOppCount + 1)
            }
        }
        return wins / Double(samples)
    }

    /// Category-only made-hand strength (fallback), 0…1. Uses the constrained
    /// evaluator; falls back to the preflop heuristic before the flop.
    static func made(hole: [Card], board: [Card]) -> Double {
        guard board.count >= 3 else { return preflop(hole) }
        let rank = HandEvaluator.evaluateOmaha(hole: hole, board: board)
        return Double(rank.category.rawValue) / Double(HandCategory.royalFlush.rawValue)
    }
}
