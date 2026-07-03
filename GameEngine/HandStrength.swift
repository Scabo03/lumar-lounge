// HandStrength.swift
// =====================================================================
// Estimating how good a holding is, from a seat's HONEST point of view: its own
// two cards plus whatever community cards are public. Never peeks at opponents'
// cards.
//
//   - Preflop: a fast heuristic (a normalised Chen score).
//   - Postflop: a seeded Monte Carlo equity estimate — deal random opponents and
//     runouts many times and count how often we win. Deterministic given the RNG
//     (D-005 style), honest (opponents are unknown, hence uniformly random —
//     range narrowing is a future refinement, D-011).
//
// Foundation only.

import Foundation

enum HandStrength {

    /// Preflop hand strength in 0…1, from a normalised Chen formula.
    static func preflop(_ hand: Hand) -> Double {
        let a = hand.cards[0].rank.rawValue
        let b = hand.cards[1].rank.rawValue
        let high = max(a, b)
        let low = min(a, b)
        let suited = hand.cards[0].suit == hand.cards[1].suit

        func highCardValue(_ rank: Int) -> Double {
            switch rank {
            case 14: return 10 // Ace
            case 13: return 8  // King
            case 12: return 7  // Queen
            case 11: return 6  // Jack
            default: return Double(rank) / 2
            }
        }

        var score = highCardValue(high)
        if high == low {
            score = Swift.max(score * 2, 5) // a pair
        } else {
            if suited { score += 2 }
            let between = high - low - 1
            switch between {
            case 0: break
            case 1: score -= 1
            case 2: score -= 2
            case 3: score -= 4
            default: score -= 5
            }
            // Small connected/one-gappers get a straight bonus.
            if between <= 1 && high <= 11 { score += 1 }
        }

        let chen = score.rounded(.up) // Chen rounds half points up
        // Chen ranges from about -1 (72o) to 20 (AA); map onto 0…1.
        return ((chen + 1) / 21).clamped01
    }

    /// Monte Carlo equity in 0…1 against `opponents` unknown hands.
    ///
    /// - Parameters:
    ///   - hole: the seat's two cards.
    ///   - board: the community cards so far (3–5 postflop).
    ///   - opponents: number of opponents still in the hand (≥ 1).
    ///   - samples: number of random rollouts.
    ///   - rng: seeded generator, so the estimate is reproducible.
    static func equity(hole: [Card], board: [Card], opponents: Int, samples: Int,
                       using rng: inout SeededGenerator) -> Double {
        let known = Set(hole + board)
        var pool = Deck().cards.filter { !known.contains($0) }
        let needCommunity = 5 - board.count
        let needed = opponents * 2 + needCommunity
        guard opponents >= 1, needCommunity >= 0, pool.count >= needed, samples > 0 else {
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
            let fullBoard = board + community
            let heroRank = HandEvaluator.evaluate(hole + fullBoard)

            // Best opponent and how many opponents share that best rank.
            var bestOpp: HandRank?
            var bestOppCount = 0
            var index = needCommunity
            for _ in 0..<opponents {
                let oppHole = [pool[index], pool[index + 1]]
                index += 2
                let oppRank = HandEvaluator.evaluate(oppHole + fullBoard)
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
                wins += 1.0 / Double(bestOppCount + 1) // split among the tied
            }
        }
        return wins / Double(samples)
    }

    /// Category-only strength (fallback), 0…1. Needs at least five cards.
    static func made(hole: [Card], board: [Card]) -> Double {
        guard hole.count + board.count >= 5 else { return preflop(Hand(hole)) }
        let rank = HandEvaluator.evaluate(hole + board)
        return Double(rank.category.rawValue) / Double(HandCategory.royalFlush.rawValue)
    }
}
