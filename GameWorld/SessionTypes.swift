// SessionTypes.swift
// =====================================================================
// The value types around a table session: a seated player and its status, the
// setup assignment, the outcome of one hand, and the errors the driver can
// raise. GameWorld only.

import Foundation
import GameEngine

/// The lifecycle status of a seated player within a session.
public enum PlayerStatus: Equatable, Sendable {
    /// In the game; dealt in whenever it has chips.
    case active
    /// Out of chips (bust). Sits out the current and following hands, but stays
    /// seated. Kept as a distinct state so a future *rebuy* can simply restore
    /// chips and set the player back to `.active` (not implemented in M1.4).
    case bustedOut
}

/// A player seated at the table during a session: identity, chips (fiches) and
/// status, at a fixed physical `position` in the ring.
public struct SessionPlayer: Equatable, Sendable {
    public let id: Int
    public internal(set) var chips: Int
    public internal(set) var status: PlayerStatus
    public let position: Int
}

/// A seat assignment used to set up a session (or to add a player later): where
/// the player sits, its id, its starting chips, and who answers for it.
public struct SeatAssignment {
    public let position: Int
    public let playerID: Int
    public let chips: Int
    public let provider: ActionProvider

    public init(position: Int, playerID: Int, chips: Int, provider: ActionProvider) {
        self.position = position
        self.playerID = playerID
        self.chips = chips
        self.provider = provider
    }
}

/// The result of one completed hand, from the session's point of view.
public struct HandOutcome: Sendable {
    /// 0-based index of this hand within the session.
    public let handNumber: Int
    /// Physical button position (ring index) used for this hand — advances by
    /// one every hand, dead button included (D-012).
    public let buttonPosition: Int
    /// Player ids that were dealt in, in clockwise order.
    public let participantIDs: [Int]
    /// The engine's raw result (pots, payouts, board, showdown…).
    public let result: HandResult
    /// Players who reached zero chips as a consequence of this hand.
    public let bustedThisHand: [Int]
    /// Chips of every seated player after the hand.
    public let chipsByPlayer: [Int: Int]
}

/// Errors the session driver can raise.
public enum SessionError: Error, Equatable, Sendable {
    /// Fewer than two players have chips: no hand can be dealt.
    case notEnoughPlayers
    /// A structural change (join/leave) was attempted while a hand is running.
    case handInProgress
    case positionOutOfRange(Int)
    case positionOccupied(Int)
    case duplicatePlayerID(Int)
    case nonPositiveChips
    case unknownPlayer(Int)
}
