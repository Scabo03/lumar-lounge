// StudTypes.swift
// =====================================================================
// The value types that surround the Seven-Card Stud Pot Limit betting engine: the
// seat configuration and its per-hand state (hole cards DOWN + up cards FACE UP), the
// five streets, the actions, the legal moves, and the result of a completed hand.
//
// These types are DELIBERATELY separate from the Texas (`Seat`/…), Draw (`DrawSeat`/…)
// and Omaha (`OmahaSeat`/…) types (D-038/D-061/D-077). The five engines are parallel
// and independent: they share only the foundational M1.1 types (Card/Rank/Suit/Deck/
// HandEvaluator) plus the game-agnostic chip arithmetic (`PotMath`/`Pot`), never each
// other's rule-bearing types. Stud is NOTHING like the others structurally — no
// community board, five betting rounds, cards dealt down AND up over the streets, an
// ANTE + BRING-IN instead of blinds, and a "highest board showing acts first" rule —
// so it earns its own engine (D-077).
//
// Foundation only. These know about chips, bets and turns — nothing about
// players-as-people, bots, UI, audio or timers.

import Foundation

// MARK: - Seat

/// The *configuration* of a seat entering a Stud hand: a position with a starting
/// stack of chips. Identity is `id`, stable across hands so callers (GameWorld) can
/// map a seat back to a player.
public struct StudSeat: Hashable, Sendable {
    public let id: Int
    public let stack: Int

    public init(id: Int, stack: Int) {
        self.id = id
        self.stack = stack
    }
}

/// The *dynamic* per-hand state of a seat, evolving as the hand is played. Unlike the
/// community-board games, a Stud seat's own cards are split into DOWN cards (private:
/// two on third street, one on seventh) and UP cards (PUBLIC: one per street on third
/// through sixth) — the up cards are the strategic heart of Stud and everyone sees them.
public struct StudSeatState: Hashable, Sendable {
    public let id: Int
    /// Chips currently in front of the seat (not yet in the pot).
    public internal(set) var stack: Int
    /// The seat's face-DOWN cards: two dealt on third street + one on seventh. PRIVATE.
    public internal(set) var holeCards: [Card]
    /// The seat's face-UP cards, dealt one per street on third–sixth. PUBLIC — every
    /// player (and every bot) legitimately sees these.
    public internal(set) var upCards: [Card]
    /// Chips committed by this seat during the *current* street.
    public internal(set) var streetBet: Int
    /// Chips committed by this seat during the *whole* hand (ante + all streets).
    public internal(set) var totalBet: Int
    /// Whether the seat has folded out of the hand.
    public internal(set) var hasFolded: Bool
    /// Whether the seat has committed its entire stack.
    public internal(set) var isAllIn: Bool
    /// Whether the seat has acted at least once during the current street. Internal:
    /// it drives betting-round completion, not part of the public API.
    var hasActed: Bool

    /// A seat that can still take an action: neither folded nor all-in.
    public var canAct: Bool { !hasFolded && !isAllIn }

    /// Every card the seat holds this hand (down + up), for showdown evaluation.
    public var allCards: [Card] { holeCards + upCards }
}

// MARK: - Street

/// The five streets of Seven-Card Stud, in order (D-077). Third street deals two down +
/// one up; fourth/fifth/sixth deal one up each; seventh ("the river") deals one down.
/// A betting round follows every street — FIVE rounds, the most of any game here.
public enum StudStreet: Int, Comparable, CaseIterable, Sendable {
    case third = 3, fourth, fifth, sixth, seventh

    public static func < (lhs: StudStreet, rhs: StudStreet) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Whether this street deals a face-UP card (third through sixth). Seventh is down.
    public var dealsUpCard: Bool { self != .seventh }
}

// MARK: - Action

/// An action a seat can take on its turn.
///
/// Amounts use **"to" semantics** (as in the other engines): `bet(n)`/`raise(n)` name
/// the *total* the seat's street bet becomes, not the delta added. Unlike No Limit, the
/// maxima are bounded by the POT LIMIT cap (see `StudLegalActions`), so a bet/raise can
/// never exceed the size of the pot. There is no explicit "bring-in" action — the
/// bring-in is a FORCED post the engine makes for the low card; a player's voluntary
/// first aggression on third street is a `raise` that "completes" to the full bet.
public enum StudAction: Hashable, Sendable {
    /// Give up the hand.
    case fold
    /// Pass when there is nothing to call (`streetBet == currentBet`).
    case check
    /// Match the current bet (all-in for less if the stack can't cover it).
    case call
    /// Open the betting on a street where no one has bet yet (fourth–seventh). The
    /// associated value is the total street bet to make (≤ the pot-limit cap).
    case bet(Int)
    /// Increase over an existing bet — including COMPLETING the bring-in to a full bet
    /// on third street. The associated value is the total street bet to raise *to*.
    case raise(Int)
    /// Commit the largest amount the rules allow: the whole stack when it fits under the
    /// pot-limit cap, otherwise a pot-sized bet/raise (an all-in-for-less call when the
    /// stack cannot even cover the call).
    case allIn
}

/// Why an attempted action was rejected. Thrown by `StudHand.apply(_:)`.
public enum StudActionError: Error, Equatable, Sendable {
    case handComplete
    case cannotCheckFacingBet
    case cannotBetFacingBet
    case betBelowMinimum(minimum: Int)
    /// The bet exceeds the Pot Limit ceiling (the size of the pot).
    case betAbovePotLimit(maximumTo: Int)
    case cannotRaiseNothingToRaise
    case raiseBelowMinimum(minimumTo: Int)
    /// The raise exceeds the Pot Limit ceiling (call + pot-after-call).
    case raiseAbovePotLimit(maximumTo: Int)
    /// A player who has already acted cannot raise over an all-in that was smaller than
    /// a full raise — the action was not reopened for them.
    case actionNotReopened
    case amountExceedsStack(maximumTo: Int)
    case nonPositiveAmount
}

// MARK: - Result

/// The outcome of a completed Stud hand.
public struct StudResult: Sendable {
    /// The pots that were formed, main pot first, then side pots.
    public let pots: [Pot]
    /// Chips won per seat id (only winners appear).
    public let payouts: [Int: Int]
    /// Stack of every seat id after payouts were applied.
    public let finalStacks: [Int: Int]
    /// Whether the hand was decided at showdown (`true`) or by everyone folding to a
    /// single seat (`false`).
    public let wentToShowdown: Bool
    /// All seven cards revealed per seat id at showdown (empty if no showdown).
    public let shownHands: [Int: [Card]]
    /// The evaluated best five-card hand per shown seat id.
    public let bestHands: [Int: HandRank]
    /// The single shared community card, if the deck was exhausted on seventh street
    /// and one had to be dealt face-up for everyone (D-077). Usually `nil`.
    public let communityCard: Card?
}

// MARK: - Legal actions

/// What the seat on turn may legally do, with the exact amounts. The bet/raise maxima
/// already fold in the POT LIMIT ceiling (never larger than the pot) AND the seat's
/// stack, so a decider can size freely within `[min…max]`. On third street, before the
/// bring-in is completed, `minRaiseTo` is the completion amount (the full bet).
public struct StudLegalActions: Equatable, Sendable {
    public let seatID: Int
    public let canFold: Bool
    public let canCheck: Bool
    public let canCall: Bool
    /// Chips required to call (may equal the stack, i.e. an all-in call).
    public let callAmount: Int
    public let canBet: Bool
    public let minBetTo: Int
    /// The pot-limit-and-stack-capped maximum opening bet (total street bet).
    public let maxBetTo: Int
    public let canRaise: Bool
    /// The minimum raise "to" — the completion amount on an uncompleted bring-in, else
    /// `currentBet + lastRaiseSize`.
    public let minRaiseTo: Int
    /// The pot-limit-and-stack-capped maximum raise (total street bet).
    public let maxRaiseTo: Int
    public let canAllIn: Bool
}
