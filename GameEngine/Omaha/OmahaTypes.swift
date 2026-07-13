// OmahaTypes.swift
// =====================================================================
// The value types that surround the Omaha Pot Limit betting engine: the seat
// configuration and its per-hand state, the four streets, the (pot-limit) actions,
// the legal moves, and the result of a completed hand.
//
// These types are DELIBERATELY separate from the Texas Hold'em types
// (`Seat`/`SeatState`/`Action`/…) and the Five-Card Draw types (D-038, D-061). The
// three engines are parallel and independent: they share only the foundational
// M1.1 types (Card/Rank/Suit/Deck/HandEvaluator) plus the game-agnostic chip
// arithmetic (`PotMath`/`Pot`), never each other's rule-bearing types.
//
// Omaha resembles Texas superficially (blinds, four community streets, side pots),
// and the temptation to reuse the Hold'em engine is strong — but the "two hole +
// three board" composition rule and the Pot Limit betting cap break it at the root
// (D-061), so Omaha owns its own types and its own hand engine.
//
// Foundation only. These know about chips, bets and turns — nothing about
// players-as-people, bots, UI, audio or timers.

import Foundation

// MARK: - Seat

/// The *configuration* of a seat entering an Omaha hand: a position with a starting
/// stack of chips. Identity is `id`, stable across hands so callers (GameWorld) can
/// map a seat back to a player.
public struct OmahaSeat: Hashable, Sendable {
    public let id: Int
    public let stack: Int

    public init(id: Int, stack: Int) {
        self.id = id
        self.stack = stack
    }
}

/// The *dynamic* per-hand state of a seat, evolving as the hand is played.
public struct OmahaSeatState: Hashable, Sendable {
    public let id: Int
    /// Chips currently in front of the seat (not yet in the pot).
    public internal(set) var stack: Int
    /// The seat's FOUR hole cards, once dealt (Omaha deals four, not two).
    public internal(set) var holeCards: [Card]
    /// Chips committed by this seat during the *current* street.
    public internal(set) var streetBet: Int
    /// Chips committed by this seat during the *whole* hand (all streets).
    public internal(set) var totalBet: Int
    /// Whether the seat has folded out of the hand.
    public internal(set) var hasFolded: Bool
    /// Whether the seat has committed its entire stack.
    public internal(set) var isAllIn: Bool
    /// Whether the seat has acted at least once during the current street.
    /// Internal: it drives betting-round completion, not part of the public API.
    var hasActed: Bool

    /// A seat that can still take an action: neither folded nor all-in.
    public var canAct: Bool { !hasFolded && !isAllIn }
}

// MARK: - Street

/// The four betting streets of Omaha, in order (identical structure to Hold'em, but
/// a distinct type — the engines never share rule-bearing types, D-038/D-061).
public enum OmahaStreet: Int, Comparable, CaseIterable, Sendable {
    case preflop, flop, turn, river

    public static func < (lhs: OmahaStreet, rhs: OmahaStreet) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Action

/// An action a seat can take on its turn.
///
/// Amounts use **"to" semantics** (as in Hold'em): `bet(n)`/`raise(n)` name the
/// *total* the seat's street bet becomes, not the delta added. Unlike No Limit
/// Hold'em, the maxima are bounded by the POT LIMIT cap (see `OmahaLegalActions`),
/// so a bet/raise can never exceed the size of the pot.
public enum OmahaAction: Hashable, Sendable {
    /// Give up the hand.
    case fold
    /// Pass when there is nothing to call (`streetBet == currentBet`).
    case check
    /// Match the current bet (all-in for less if the stack can't cover it).
    case call
    /// Open the betting on a street where no one has bet yet. Postflop only.
    /// The associated value is the total street bet to make (≤ the pot-limit cap).
    case bet(Int)
    /// Increase over an existing bet. The associated value is the total street bet
    /// to raise *to* (≤ the pot-limit cap).
    case raise(Int)
    /// Commit the largest amount the rules allow: the whole stack when it fits under
    /// the pot-limit cap, otherwise a pot-sized bet/raise (an all-in-for-less call
    /// when the stack cannot even cover the call).
    case allIn
}

/// Why an attempted action was rejected. Thrown by `OmahaHand.apply(_:)`.
public enum OmahaActionError: Error, Equatable, Sendable {
    case handComplete
    case cannotCheckFacingBet
    case cannotCallNothingToCall
    case cannotBetFacingBet
    case betBelowMinimum(minimum: Int)
    /// The bet exceeds the Pot Limit ceiling (the size of the pot).
    case betAbovePotLimit(maximumTo: Int)
    case cannotRaiseNothingToRaise
    case raiseBelowMinimum(minimumTo: Int)
    /// The raise exceeds the Pot Limit ceiling (call + pot-after-call).
    case raiseAbovePotLimit(maximumTo: Int)
    /// A player who has already acted cannot raise over an all-in that was smaller
    /// than a full raise — the action was not reopened for them.
    case actionNotReopened
    case amountExceedsStack(maximumTo: Int)
    case nonPositiveAmount
}

// MARK: - Result

/// The outcome of a completed Omaha hand.
public struct OmahaResult: Sendable {
    /// The pots that were formed, main pot first, then side pots.
    public let pots: [Pot]
    /// Chips won per seat id (only winners appear).
    public let payouts: [Int: Int]
    /// Stack of every seat id after payouts were applied.
    public let finalStacks: [Int: Int]
    /// Whether the hand was decided at showdown (`true`) or by everyone folding to a
    /// single seat (`false`).
    public let wentToShowdown: Bool
    /// The community cards on the board at the end of the hand.
    public let board: [Card]
    /// The four hole cards revealed per seat id at showdown (empty if no showdown).
    public let shownHands: [Int: [Card]]
    /// The evaluated best CONSTRAINED hand (two hole + three board) per shown seat id.
    public let bestHands: [Int: HandRank]
}

// MARK: - Legal actions

/// What the seat on turn may legally do, with the exact amounts. The bet/raise
/// maxima already fold in the POT LIMIT ceiling (never larger than the pot) AND the
/// seat's stack, so a decider can size freely within `[min…max]`.
public struct OmahaLegalActions: Equatable, Sendable {
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
    public let minRaiseTo: Int
    /// The pot-limit-and-stack-capped maximum raise (total street bet).
    public let maxRaiseTo: Int
    public let canAllIn: Bool
}
