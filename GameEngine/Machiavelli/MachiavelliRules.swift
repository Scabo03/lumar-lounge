// MachiavelliRules.swift
// =====================================================================
// THE VALIDITY PREDICATE — the single source of truth on legality for Machiavelli
// (D-070, CONVENTIONS §4). Everything downstream (the turn model, the bots, and the
// two future UIs) asks THESE pure functions whether a set of cards is a legal
// combination and whether a whole table is valid. The predicate lives in the engine
// and NEVER in the UI, on purpose: a future blind player will compose a combination
// inside a box and the confirm button unlocks when the SELECTION is legal
// (`classify`), while a future sighted player will drag cards onto the table and the
// end-turn buttons unlock when the TABLE is valid (`isValidTable`). Two interfaces,
// one predicate — so a bug can't make the two players play subtly different games,
// and sighted and blind play provably the same Machiavelli.
//
// Canonical rules fixed here (D-070):
//  • Two 52-card decks, 104 cards, NO wildcards.
//  • Group ("tris"/"poker"): 3–4 cards of the same RANK, all DISTINCT suits.
//  • Run ("scala"): 3+ consecutive cards of the same SUIT.
//  • The ace may sit at EITHER end of a run — high (Q-K-A) or low (A-2-3) — but never
//    wraps around (K-A-2 is illegal).
//
// Foundation only.

import Foundation

public enum MachiavelliRules {

    // MARK: - The public predicate (single source of truth)

    /// Classifies a set of cards as a legal combination, returning its form, or `nil`
    /// if the cards do not form any legal combination. Order-independent. This is the
    /// predicate a "compose in a box" UI queries to unlock its confirm button.
    public static func classify(_ cards: [Card]) -> MeldForm? {
        classified(cards)?.0
    }

    /// Whether a set of cards forms ANY legal combination.
    public static func isValidCombination(_ cards: [Card]) -> Bool {
        classified(cards) != nil
    }

    /// Whether a whole table — a list of proposed combinations — is fully valid:
    /// non-empty, and every combination legal. This is the predicate a "drag onto the
    /// table" UI queries to unlock its end-turn buttons.
    public static func isValidTable(_ arrangement: [[Card]]) -> Bool {
        arrangement.allSatisfy { !$0.isEmpty && isValidCombination($0) }
    }

    // MARK: - Classification with canonical ordering

    /// The workhorse: classifies `cards` and, when legal, returns the form together
    /// with the cards in canonical order (groups ordered by suit; runs ascending with
    /// the ace at the end it plays). `Meld` is built on top of this.
    static func classified(_ cards: [Card]) -> (MeldForm, [Card])? {
        guard cards.count >= MachiavelliConstants.minMeldSize else { return nil }
        if let group = asGroup(cards) { return (.group, group) }
        if let run = asRun(cards) { return (.run, run) }
        return nil
    }

    /// A group: 3–4 cards, all the same rank, all of DISTINCT suits. Two identical
    /// cards (possible with two decks) share a suit, so they can never sit in one
    /// group. Returned ordered by the fixed suit order.
    private static func asGroup(_ cards: [Card]) -> [Card]? {
        guard (MachiavelliConstants.minMeldSize...MachiavelliConstants.maxGroupSize).contains(cards.count) else { return nil }
        let rank = cards[0].rank
        guard cards.allSatisfy({ $0.rank == rank }) else { return nil }
        let suits = cards.map { $0.suit }
        guard Set(suits).count == cards.count else { return nil }   // all distinct
        return cards.sorted { $0.suit.rawValue < $1.suit.rawValue }
    }

    /// A run: 3+ cards, all the same suit, consecutive ranks. The ace may play high
    /// (…Q-K-A) or low (A-2-3…) but not both at once (no wrap). Returned ascending,
    /// with the ace placed at whichever end made the sequence consecutive.
    private static func asRun(_ cards: [Card]) -> [Card]? {
        guard cards.count >= MachiavelliConstants.minMeldSize else { return nil }
        let suit = cards[0].suit
        guard cards.allSatisfy({ $0.suit == suit }) else { return nil }

        let ranks = cards.map { $0.rank.rawValue }         // ace == 14
        guard Set(ranks).count == cards.count else { return nil }  // no repeated rank

        // Ace-high interpretation (ranks as-is): consecutive?
        if isConsecutive(ranks) {
            return cards.sorted { $0.rank.rawValue < $1.rank.rawValue }
        }
        // Ace-low interpretation (ace counts as 1): only relevant if an ace is present.
        if ranks.contains(14) {
            // Map ace→1; a natural rank-1 does not exist, so no collision is possible.
            let low = cards.map { ($0, $0.rank == .ace ? 1 : $0.rank.rawValue) }
            if isConsecutive(low.map { $0.1 }) {
                return low.sorted { $0.1 < $1.1 }.map { $0.0 }
            }
        }
        return nil
    }

    /// Whether the integer values form a gap-free ascending run (after sorting).
    private static func isConsecutive(_ values: [Int]) -> Bool {
        let sorted = values.sorted()
        for i in 1..<sorted.count where sorted[i] != sorted[i - 1] + 1 { return false }
        return true
    }

    // MARK: - Deck / shoe

    /// Builds the Machiavelli shoe: two full 52-card decks combined (104 cards), then
    /// shuffled reproducibly from `seed` (production passes a fresh random seed, tests
    /// a fixed one — D-047 lives in the driver, not here). Returns the shuffled cards;
    /// the caller deals hands off the top and keeps the rest as the stock.
    public static func shoe(seed: UInt64) -> [Card] {
        var cards: [Card] = []
        cards.reserveCapacity(MachiavelliConstants.totalCards)
        for _ in 0..<MachiavelliConstants.deckCount {
            for suit in Suit.allCases {
                for rank in Rank.allCases {
                    cards.append(Card(rank, suit))
                }
            }
        }
        var generator = SeededGenerator(seed: seed)
        cards.shuffle(using: &generator)
        return cards
    }
}
