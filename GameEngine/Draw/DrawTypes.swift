// DrawTypes.swift
// =====================================================================
// The value types that surround the Five-Card Draw betting engine: the seat
// configuration and its per-hand state, the phases of a hand, the (limit)
// actions a player can take, the draw request, the legal moves, and the result
// of a completed deal.
//
// These types are DELIBERATELY separate from the Texas Hold'em types
// (`Seat`/`SeatState`/`Action`/…). The two engines are parallel and independent
// (D-038): they share only the foundational M1.1 types (Card/Rank/Suit/Deck/
// HandEvaluator) plus the game-agnostic chip arithmetic (`PotMath`/`Pot`), never
// each other's rule-bearing types.
//
// Foundation only. These know about chips, bets, draws and turns — nothing about
// players-as-people, bots, UI, audio or timers.

import Foundation

// MARK: - Phase

/// The phases of a single Five-Card Draw deal, in order.
///
/// Traditional draw has exactly two betting rounds around one card exchange:
/// no flop/turn/river. `.complete` marks a finished (or passed-in) deal.
public enum DrawPhase: Int, Comparable, CaseIterable, Sendable {
    /// First betting round (before the draw): opens on jacks-or-better, small bet.
    case firstBet
    /// The card exchange: each live seat discards 0–4 cards and draws replacements.
    case draw
    /// Second betting round (after the draw): big bet.
    case secondBet
    /// The deal is over (showdown, fold-out, or passed in).
    case complete

    public static func < (lhs: DrawPhase, rhs: DrawPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Seat

/// The *configuration* of a seat entering a deal: a position with a starting
/// stack of chips (fiches). Identity is `id`, stable across deals.
public struct DrawSeat: Hashable, Sendable {
    public let id: Int
    public let stack: Int

    public init(id: Int, stack: Int) {
        self.id = id
        self.stack = stack
    }
}

/// The *dynamic* per-deal state of a seat, evolving as the hand is played.
public struct DrawSeatState: Hashable, Sendable {
    public let id: Int
    /// Chips currently in front of the seat (not yet in the pot).
    public internal(set) var stack: Int
    /// The seat's five cards. Always exactly five once dealt; some are replaced
    /// during the draw. Kept sorted by descending rank for readability.
    public internal(set) var cards: [Card]
    /// Chips committed by this seat during the *current* betting round.
    public internal(set) var streetBet: Int
    /// Chips committed by this seat during the *whole* deal (ante + both rounds).
    public internal(set) var totalBet: Int
    /// Whether the seat has folded out of the deal.
    public internal(set) var hasFolded: Bool
    /// Whether the seat has committed its entire stack.
    public internal(set) var isAllIn: Bool
    /// Whether the seat opened the pot (made the first voluntary bet in round 1).
    public internal(set) var isOpener: Bool
    /// The cards that justified the open (a jacks-or-better pair, or the whole
    /// qualifying combination), snapshotted AT the moment of opening — preserved
    /// even if the seat later discards them in the draw. `nil` when the seat did
    /// not open, OR opened without the goods (an illegal open, punished at
    /// showdown — see D-039).
    public internal(set) var openers: [Card]?
    /// How many cards the seat exchanged in the draw (once it has drawn).
    public internal(set) var discardCount: Int
    /// Whether the seat has taken its draw turn.
    public internal(set) var hasDrawn: Bool
    /// Whether the seat has acted at least once during the current betting round.
    /// Internal: it drives round completion, not part of the public API.
    var hasActed: Bool

    /// A seat that can still take a betting action: neither folded nor all-in.
    public var canAct: Bool { !hasFolded && !isAllIn }
    /// A seat still contesting the pot (not folded), whether or not it can bet.
    public var isLive: Bool { !hasFolded }
}

// MARK: - Action

/// An action a seat can take on its turn in a betting round.
///
/// Five-Card Draw here is **limit**: bet and raise sizes are fixed by the table
/// (small bet before the draw, big bet after), so — unlike No Limit Hold'em —
/// the actions carry no amount. `bet` opens; `raise` re-raises; the round is
/// capped at four escalations (bet + three raises).
public enum DrawAction: Hashable, Sendable {
    /// Give up the hand.
    case fold
    /// Pass when there is nothing to call.
    case check
    /// Match the current bet (all-in for less if the stack can't cover it).
    case call
    /// Open the betting for one bet unit. Legal only when no one has bet this
    /// round. Anyone may physically open; whether the open was *legitimate*
    /// (jacks or better) is judged at showdown (D-039).
    case bet
    /// Raise the current bet by one bet unit. Legal while under the raise cap.
    case raise
}

/// Why an attempted action was rejected. Thrown by `FiveCardDrawHand.apply(_:)`.
public enum DrawActionError: Error, Equatable, Sendable {
    case handComplete
    case notInBettingPhase
    case cannotCheckFacingBet
    case cannotCallNothingToCall
    case cannotBetFacingBet
    case cannotRaiseNothingToRaise
    /// The betting round has already reached its raise cap (bet + three raises).
    case raiseCapReached
    /// A player who has already acted cannot raise over an all-in that was
    /// smaller than a full raise — the action was not reopened for them.
    case actionNotReopened
    case noChipsToBet
}

/// Why a draw request was rejected. Thrown by `FiveCardDrawHand.discard(_:)`.
public enum DrawExchangeError: Error, Equatable, Sendable {
    case notInDrawPhase
    case notThisSeatsTurn
    /// More than four cards were offered for exchange.
    case tooManyDiscards
    /// A card offered for exchange is not in the seat's hand (or was repeated).
    case cardNotHeld(Card)
}

// MARK: - Result

/// How a Five-Card Draw deal ended.
public enum DrawOutcome: Equatable, Sendable {
    /// Decided at showdown among two or more live seats.
    case showdown
    /// Everyone but one seat folded; no showdown.
    case foldOut
    /// No one opened the first betting round: the deal is void and its antes
    /// carry forward into the next deal's pot (pass-and-out, variant B, D-040).
    case passedIn
}

/// The outcome of a completed Five-Card Draw deal.
public struct DrawResult: Sendable {
    /// How the deal ended.
    public let outcome: DrawOutcome
    /// The pots that were formed, main pot first (empty when passed in).
    public let pots: [Pot]
    /// Chips won per seat id (only winners appear; empty when passed in).
    public let payouts: [Int: Int]
    /// Stack of every seat id after payouts were applied.
    public let finalStacks: [Int: Int]
    /// Whether the deal was decided at showdown.
    public let wentToShowdown: Bool
    /// The five-card hand revealed per live seat id at showdown (empty otherwise).
    public let revealedHands: [Int: [Card]]
    /// The evaluated rank per revealed seat id (empty when no showdown).
    public let bestHands: [Int: HandRank]
    /// The seat that opened the pot, if any.
    public let openerSeatID: Int?
    /// `true` when the opener reached showdown but could not prove openers and was
    /// therefore disqualified — it lost regardless of its final hand (D-039).
    public let openerDisqualified: Bool
    /// Chips carried forward when `outcome == .passedIn` (this deal's antes plus
    /// any pot already carried in); 0 otherwise.
    public let carriedPot: Int
}

// MARK: - Legal actions

/// What the seat on turn may legally do in a betting round, plus the fixed bet
/// unit and whether it actually holds openers.
public struct DrawLegalActions: Equatable, Sendable {
    public let seatID: Int
    public let canFold: Bool
    public let canCheck: Bool
    public let canCall: Bool
    /// Chips required to call (may equal the stack, i.e. an all-in call).
    public let callAmount: Int
    /// Whether the seat may open the pot (no bet yet this round, has chips).
    public let canBet: Bool
    /// Whether the seat may raise (facing a bet, under the cap, action open).
    public let canRaise: Bool
    /// The fixed size of a bet/raise this round (small bet round 1, big bet round 2).
    public let betUnit: Int
    /// Raises still permitted this round (0 once the cap is reached).
    public let raisesRemaining: Int
    /// Whether the seat currently holds jacks-or-better — i.e. whether opening
    /// now would be *provable* at showdown. Deciders should consult this; the
    /// engine does not force it (honour system, D-039).
    public let hasOpeners: Bool
}

// MARK: - Draw options

/// The exchange options for the seat whose draw turn it is: its current five
/// cards and how many it may discard (0…4).
public struct DrawOptions: Equatable, Sendable {
    public let seatID: Int
    public let cards: [Card]
    public let maxDiscards: Int
}
