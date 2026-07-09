// DrawSessionTypes.swift
// =====================================================================
// The value types around a Five-Card Draw table session: a seated player, the
// setup assignment, the outcome of one deal, and the driver's errors. Dedicated
// to the draw driver (D-042) — parallel to the Texas `SessionTypes`, sharing only
// the game-agnostic `PlayerStatus`. GameWorld only.

import Foundation
import GameEngine

/// A player seated at a draw table during a session: identity, chips (fiches),
/// status, at a fixed physical `position` in the ring. Mirrors the Texas
/// `SessionPlayer`; kept separate so the two drivers don't couple.
public struct DrawSessionPlayer: Equatable, Sendable {
    public let id: Int
    public internal(set) var chips: Int
    public internal(set) var status: PlayerStatus
    public let position: Int
}

/// A seat assignment used to set up a draw session (or add a player later).
public struct DrawSeatAssignment {
    public let position: Int
    public let playerID: Int
    public let chips: Int
    public let provider: DrawActionProvider

    public init(position: Int, playerID: Int, chips: Int, provider: DrawActionProvider) {
        self.position = position
        self.playerID = playerID
        self.chips = chips
        self.provider = provider
    }
}

/// The result of one completed deal, from the session's point of view. A deal that
/// was passed in (nobody opened) is reported too, with `wasPlayed == false`.
public struct DrawHandOutcome: Sendable {
    /// 0-based index of this PLAYED hand within the session (passed-in deals do
    /// not advance it).
    public let handNumber: Int
    /// Physical button position used for this deal.
    public let buttonPosition: Int
    /// Player ids that were dealt in, clockwise.
    public let participantIDs: [Int]
    /// The engine's raw result.
    public let result: DrawResult
    /// Whether the deal was actually played (false when passed in).
    public let wasPlayed: Bool
    /// The progressive pot carried FORWARD after this deal (0 when a deal was
    /// played and its pot awarded).
    public let carriedPot: Int
    /// How many consecutive deals have now been passed in (0 once one is played).
    public let consecutivePassed: Int
    /// Players who reached zero chips as a consequence of this deal.
    public let bustedThisHand: [Int]
    /// Chips of every seated player after the deal.
    public let chipsByPlayer: [Int: Int]
}

/// Errors the draw session driver can raise. Mirrors `SessionError`.
public enum DrawSessionError: Error, Equatable, Sendable {
    case notEnoughPlayers
    case handInProgress
    case sessionEnded
    case positionOutOfRange(Int)
    case positionOccupied(Int)
    case duplicatePlayerID(Int)
    case nonPositiveChips
    case unknownPlayer(Int)
}
