// BlackjackValue.swift
// =====================================================================
// The arithmetic of a blackjack hand: card points, hard/soft totals,
// bust and natural detection.
//
// Pure and free-standing (Foundation only). This is the piece every other
// part of the blackjack engine — and every readout the player hears — is
// built on, so it lives alone and is exhaustively testable.
//
// Note on `Rank.rawValue`: the foundational `Rank` follows the ACE-HIGH
// poker convention (ace == 14, jack/queen/king == 11/12/13). Blackjack
// counts differently (ace == 1 or 11, all face cards == 10), so this file
// owns its own mapping rather than reinterpreting the shared raw values.

import Foundation

/// Point arithmetic for blackjack hands.
public enum BlackjackValue {

    /// The blackjack point value of a rank, counting an ace as its LOW value.
    ///
    /// Face cards are worth ten; the ace is worth one here, and the extra ten
    /// that may promote it to eleven is applied by `total(_:)`, which is the
    /// only place that knows whether the promotion still fits under 21.
    public static func points(_ rank: Rank) -> Int {
        switch rank {
        case .ace:                        return 1
        case .jack, .queen, .king, .ten:  return 10
        default:                          return rank.rawValue
        }
    }

    /// The best total for a set of cards, plus whether that total is *soft*.
    ///
    /// A total is **soft** when it counts an ace as eleven and could still
    /// fall back to one without busting — the distinction a player needs,
    /// because a soft hand cannot bust on the next card.
    ///
    /// - Returns: the highest total at or below 21 when one exists, otherwise
    ///   the hard total (which is a bust).
    public static func total(_ cards: [Card]) -> (total: Int, isSoft: Bool) {
        let hard = cards.reduce(0) { $0 + points($1.rank) }
        let hasAce = cards.contains { $0.rank == .ace }
        if hasAce && hard + 10 <= 21 {
            return (hard + 10, true)
        }
        return (hard, false)
    }

    /// The best total for a set of cards, discarding the softness flag.
    public static func total(of cards: [Card]) -> Int {
        total(cards).total
    }

    /// Whether the hand has gone over 21.
    public static func isBust(_ cards: [Card]) -> Bool {
        total(cards).total > 21
    }

    /// Whether the hand is a *natural*: 21 on exactly the first two cards.
    ///
    /// Only the caller knows whether the hand came from a split — a 21 built
    /// after splitting is an ordinary 21 by house rule (D-090) — so this
    /// function answers the shape question only and the round applies the
    /// split provision.
    public static func isNatural(_ cards: [Card]) -> Bool {
        cards.count == 2 && total(cards).total == 21
    }

    /// Whether two cards may be split: same point VALUE, not necessarily the
    /// same rank. A king beside a ten is a legal split under the house rule.
    public static func canSplit(_ cards: [Card]) -> Bool {
        cards.count == 2 && points(cards[0].rank) == points(cards[1].rank)
    }
}
