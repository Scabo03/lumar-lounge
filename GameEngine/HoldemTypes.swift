// HoldemTypes.swift
// =====================================================================
// The value types that surround the Texas Hold'em betting engine: the seat
// configuration and its per-hand state, the streets, the actions a player can
// take, the pots, and the result of a completed hand.
//
// Foundation only. These types know about chips, bets and turns — but nothing
// about players-as-people, bots, UI, audio or timers (those live in GameWorld /
// UI / Audio). See ../CLAUDE.md and CONVENTIONS.md.

import Foundation

// MARK: - Seat

/// The *configuration* of a seat entering a hand: a position at the table with
/// a starting stack of chips (fiches). Identity is the `id`, stable across
/// hands so callers (GameWorld) can map a seat back to a player.
public struct Seat: Hashable, Sendable {
    public let id: Int
    public let stack: Int

    public init(id: Int, stack: Int) {
        self.id = id
        self.stack = stack
    }
}

/// The *dynamic* per-hand state of a seat, evolving as the hand is played.
public struct SeatState: Hashable, Sendable {
    public let id: Int
    /// Chips currently in front of the seat (not yet in the pot).
    public internal(set) var stack: Int
    /// The seat's two hole cards, once dealt.
    public internal(set) var hole: Hand?
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

/// The four betting streets of Texas Hold'em, in order.
public enum Street: Int, Comparable, CaseIterable, Sendable {
    case preflop, flop, turn, river

    public static func < (lhs: Street, rhs: Street) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Action

/// An action a seat can take on its turn.
///
/// Amounts use **"to" semantics**: `bet(n)` and `raise(n)` name the *total* the
/// seat's street bet becomes, not the delta added. So over a big blind of 10,
/// `raise(30)` means "make it 30 to go" (the seat adds `30 - alreadyIn`).
public enum Action: Equatable, Sendable {
    /// Give up the hand.
    case fold
    /// Pass when there is nothing to call (`streetBet == currentBet`).
    case check
    /// Match the current bet (all-in for less if the stack can't cover it).
    case call
    /// Open the betting on a street where no one has bet yet. Postflop only.
    /// The associated value is the total street bet to make.
    case bet(Int)
    /// Increase over an existing bet. The associated value is the total street
    /// bet to raise *to*.
    case raise(Int)
    /// Commit the entire remaining stack (resolves to a call, bet or raise).
    case allIn
}

/// Why an attempted action was rejected. Thrown by `HoldemHand.apply(_:)`.
public enum ActionError: Error, Equatable, Sendable {
    case handComplete
    case cannotCheckFacingBet
    case cannotCallNothingToCall
    case cannotBetFacingBet
    case betBelowMinimum(minimum: Int)
    case cannotRaiseNothingToRaise
    case raiseBelowMinimum(minimumTo: Int)
    /// A player who has already acted cannot raise over an all-in that was
    /// smaller than a full raise — the action was not reopened for them.
    case actionNotReopened
    case amountExceedsStack(maximumTo: Int)
    case nonPositiveAmount
}

// MARK: - Pot

/// A single pot (main or side): an amount of chips and the seats eligible to
/// win it. A seat is eligible if it contributed to this pot's level and has not
/// folded.
public struct Pot: Equatable, Sendable {
    public let amount: Int
    public let eligibleSeatIDs: [Int]

    public init(amount: Int, eligibleSeatIDs: [Int]) {
        self.amount = amount
        self.eligibleSeatIDs = eligibleSeatIDs
    }
}

// MARK: - Result

/// The outcome of a completed hand.
public struct HandResult: Sendable {
    /// The pots that were formed, main pot first, then side pots.
    public let pots: [Pot]
    /// Chips won per seat id (only winners appear).
    public let payouts: [Int: Int]
    /// Stack of every seat id after payouts were applied.
    public let finalStacks: [Int: Int]
    /// Whether the hand was decided at showdown (`true`) or by everyone folding
    /// to a single seat (`false`).
    public let wentToShowdown: Bool
    /// The community cards on the board at the end of the hand.
    public let board: [Card]
    /// Hole cards revealed at showdown, per seat id (empty if no showdown).
    public let shownHands: [Int: Hand]
    /// The evaluated best hand per shown seat id (empty if no showdown).
    public let bestHands: [Int: HandRank]
}

// MARK: - Legal actions

/// A description of what the seat on turn may legally do, with the exact
/// amounts. Useful for validating input and, later, for driving UI and bots.
public struct LegalActions: Equatable, Sendable {
    public let seatID: Int
    public let canFold: Bool
    public let canCheck: Bool
    /// Chips required to call (may equal the stack, i.e. an all-in call).
    public let canCall: Bool
    public let callAmount: Int
    public let canBet: Bool
    public let minBetTo: Int
    public let maxBetTo: Int
    public let canRaise: Bool
    public let minRaiseTo: Int
    public let maxRaiseTo: Int
    public let canAllIn: Bool
}
