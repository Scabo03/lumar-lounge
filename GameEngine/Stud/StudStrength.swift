// StudStrength.swift
// =====================================================================
// Estimating how good a Stud holding is, from a seat's HONEST point of view: its own
// seven-in-progress cards plus every up card visible on the table. Never peeks at
// opponents' DOWN cards.
//
//   - Third street (three cards): a fast heuristic — rolled-up trips and big pairs are
//     gold, three to a flush/straight and big live cards are playable.
//   - Later streets: a seeded Monte Carlo equity estimate. Every unknown card is drawn
//     from the deck with the visible up cards REMOVED, so dead cards (an opponent
//     holding a card the hero needs) honestly shrink the hero's equity. Opponents keep
//     their visible up cards and get random hidden cards; each hand completed to seven,
//     best five evaluated, wins counted. Deterministic given the RNG (D-011 spirit).
//
// The BOARD-READING dial (`Personality.studBoardReading`, D-076) is applied by the bot
// on top of this: `boardThreat` measures how scary opponents' up cards look, and the bot
// demands more to continue in proportion to how much it reads the boards.
//
// Foundation only.

import Foundation

enum StudStrength {

    /// Third-street strength in 0…1 over the three cards (2 down + 1 up). Rewards rolled-up
    /// trips, pairs (high best), three to a flush, three to a straight, and big cards.
    static func thirdStreet(_ cards: [Card]) -> Double {
        guard cards.count == 3 else { return 0 }
        let ranks = cards.map { $0.rank.rawValue }.sorted(by: >)
        var counts: [Int: Int] = [:]
        for r in ranks { counts[r, default: 0] += 1 }
        let maxCount = counts.values.max() ?? 1

        if maxCount == 3 { return 0.98 }                       // rolled up — monster
        if maxCount == 2 {
            let pairRank = counts.first { $0.value == 2 }!.key
            return (0.55 + Double(pairRank - 2) / 12.0 * 0.35).clamped01   // 0.55 (22) … 0.90 (AA)
        }

        // Three distinct cards: reward flush/straight potential and high cards.
        var score = 0.0
        let suits = Set(cards.map { $0.suit })
        if suits.count == 1 { score += 0.35 }                  // three to a flush
        let span = ranks[0] - ranks[2]
        if Set(ranks).count == 3 && span <= 4 { score += 0.25 } // three to a straight (gapped ok)
        // High-card component (top card matters most).
        score += Double(ranks[0] - 2) / 12.0 * 0.30
        score += Double(ranks[1] - 2) / 12.0 * 0.12
        score += Double(ranks[2] - 2) / 12.0 * 0.05
        return score.clamped01
    }

    /// Monte Carlo equity in 0…1 against `opponents` unknown hands, completing every hand
    /// to seven cards. `heroCards` are the hero's current cards, `opponentUpCards` the
    /// visible up cards of each active opponent. Deterministic given the RNG.
    static func equity(heroCards: [Card], opponentUpCards: [[Card]], samples: Int,
                       using rng: inout SeededGenerator) -> Double {
        let opponents = opponentUpCards.count
        guard opponents >= 1, heroCards.count >= 3 else { return made(heroCards) }

        let known = Set(heroCards + opponentUpCards.flatMap { $0 })
        var pool = Deck().cards.filter { !known.contains($0) }
        let heroNeed = 7 - heroCards.count
        let oppNeed = opponentUpCards.map { 7 - $0.count }
        let needed = heroNeed + oppNeed.reduce(0, +)
        guard needed >= 0, pool.count >= needed, samples > 0 else { return made(heroCards) }

        var wins = 0.0
        for _ in 0..<samples {
            let count = pool.count
            for i in 0..<needed {                              // partial Fisher–Yates
                let j = i + Int(rng.next() % UInt64(count - i))
                pool.swapAt(i, j)
            }
            var cursor = 0
            let heroFull = heroCards + Array(pool[cursor..<cursor + heroNeed])
            cursor += heroNeed
            let heroRank = HandEvaluator.evaluate(heroFull)

            var bestOpp: HandRank?
            var bestOppCount = 0
            for o in 0..<opponents {
                let need = oppNeed[o]
                let oppFull = opponentUpCards[o] + Array(pool[cursor..<cursor + need])
                cursor += need
                let oppRank = HandEvaluator.evaluate(oppFull)
                if bestOpp == nil || oppRank > bestOpp! { bestOpp = oppRank; bestOppCount = 1 }
                else if oppRank == bestOpp! { bestOppCount += 1 }
            }

            if bestOpp == nil || heroRank > bestOpp! { wins += 1 }
            else if heroRank == bestOpp! { wins += 1.0 / Double(bestOppCount + 1) }
        }
        return wins / Double(samples)
    }

    /// Category-only made-hand strength (fallback), 0…1, over whatever cards are known.
    static func made(_ cards: [Card]) -> Double {
        guard cards.count >= 5 else { return thirdStreet(Array(cards.prefix(3))) }
        let rank = HandEvaluator.evaluate(cards)
        return Double(rank.category.rawValue) / Double(HandCategory.royalFlush.rawValue)
    }

    /// How threatening one opponent's up cards look, 0…1 (D-076): a pair/trips showing,
    /// or three-plus to a flush or a straight. This is the READABLE danger a sharp player
    /// weighs — pure description of public cards, not a peek at the down cards.
    static func boardThreat(_ upCards: [Card]) -> Double {
        guard upCards.count >= 2 else { return 0 }
        var counts: [Int: Int] = [:]
        for c in upCards { counts[c.rank.rawValue, default: 0] += 1 }
        let maxRankCount = counts.values.max() ?? 1
        var threat = 0.0
        if maxRankCount >= 3 { threat = max(threat, 0.85) }        // trips showing
        else if maxRankCount == 2 { threat = max(threat, 0.45) }   // pair showing

        // Flush danger: three or four to a suit in the up cards.
        var suitCounts: [Suit: Int] = [:]
        for c in upCards { suitCounts[c.suit, default: 0] += 1 }
        if let s = suitCounts.values.max() {
            if s >= 4 { threat = max(threat, 0.75) }
            else if s == 3 { threat = max(threat, 0.35) }
        }

        // Straight danger: three or four to a straight (tight span among distinct ranks).
        let distinct = Set(upCards.map { $0.rank.rawValue }).sorted()
        if distinct.count >= 3 {
            let span = distinct.last! - distinct.first!
            if span <= 4 { threat = max(threat, distinct.count >= 4 ? 0.55 : 0.30) }
        }
        return threat
    }
}
