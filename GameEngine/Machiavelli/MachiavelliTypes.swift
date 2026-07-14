// MachiavelliTypes.swift
// =====================================================================
// The value types of the Machiavelli engine: what a legal combination (meld) is,
// and the errors a turn can raise. Machiavelli is the Italian recombination game —
// NOT poker: no pot, no bets, no blinds, no bluff, no showdown. Players lay down
// valid combinations (runs and groups) and may FREELY dismantle and recompose any
// combination already on the table (their own or an opponent's), as long as the
// table is fully valid when their turn ends. First to empty their hand wins.
//
// This engine is a NEW ANIMAL. It lives in its own subfolder and shares NOTHING
// rule-bearing with Texas/Draw/Omaha (CONVENTIONS §1, D-038): it imports none of
// them, and reuses only the foundational M1.1 types (Card/Rank/Suit/Deck). None of
// poker's machinery (BotContext-with-equity, Pot, side pots, risk/aggression dials)
// is reused here — it would not fit.
//
// Foundation only. These types know about cards and combinations — nothing about
// players-as-people, bots, UI, audio or timers.
//
// See the "Machiavelli canonical rules" decision (D-070) for the full ruleset.

import Foundation

// MARK: - Constants

/// The fixed rules constants of this Machiavelli ruleset (D-070).
public enum MachiavelliConstants {
    /// Machiavelli is played with TWO standard 52-card decks combined — 104 cards,
    /// NO jokers/wildcards. The absence of wildcards is deliberate and is what makes
    /// the recombination pure: every card is exactly itself (D-070).
    public static let deckCount = 2
    /// Total cards in the shoe: 104.
    public static let totalCards = 52 * deckCount
    /// Cards dealt to each player at the start of a game.
    public static let handSize = 13
    /// The minimum size of any valid combination (both runs and groups).
    public static let minMeldSize = 3
    /// The maximum size of a group: one card per suit, so four.
    public static let maxGroupSize = 4
}

// MARK: - Meld

/// The two shapes a legal combination can take.
public enum MeldForm: Equatable, Sendable {
    /// A "tris"/"poker" — 3 or 4 cards of the SAME rank, all of DISTINCT suits.
    case group
    /// A "scala" — 3 or more consecutive cards of the SAME suit.
    case run
}

/// A validated combination on the table. It can only be constructed from cards that
/// form a legal combination (failable init), so a `Meld` value is ALWAYS valid; its
/// `cards` are stored in canonical order (groups by suit, runs ascending with the ace
/// placed at the end it plays). The rules live in `MachiavelliRules` — this type is a
/// thin, always-legal wrapper over them.
public struct Meld: Equatable, Sendable {
    public let cards: [Card]
    public let form: MeldForm

    /// Builds a meld, or returns `nil` if the cards are not a legal combination.
    public init?(_ cards: [Card]) {
        guard let (form, ordered) = MachiavelliRules.classified(cards) else { return nil }
        self.cards = ordered
        self.form = form
    }

    public var size: Int { cards.count }
}

// MARK: - Errors

/// Why a proposed table arrangement was rejected. The turn model (`MachiavelliTurnContext`)
/// validates every proposal against the SAME predicate the UI will query, so a rejection
/// here is the exact reason a "confirm"/"end turn" button would stay locked.
public enum MachiavelliRejection: Error, Equatable, Sendable {
    /// A proposed combination is empty.
    case emptyCombination
    /// A proposed group of cards is not a legal run or group.
    case invalidCombination([Card])
    /// The arrangement drops a card that was on the table at the start of the turn —
    /// you may rearrange table cards among combinations but never take one into hand.
    case removedTableCard
    /// The arrangement uses a card that is neither on the table nor in the hand.
    case usedUnavailableCard
}

/// Why a session-level turn action failed.
public enum MachiavelliError: Error, Equatable, Sendable {
    case gameOver
    case notPlayersTurn
    case cannotPassWithoutMelding
    case cannotDrawAfterMelding
    case invalidArrangement(MachiavelliRejection)
}
