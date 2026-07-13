// OmahaSessionTypes.swift
// =====================================================================
// The session-level value types for an Omaha table: the seated player, the seat
// assignment that binds a player to an action provider, the per-hand outcome, and
// the session errors. Parallel to the Texas (`SessionTypes`) and Draw
// (`DrawSessionTypes`) equivalents — the drivers never share rule-bearing types —
// but reusing the game-agnostic `PlayerStatus`.
//
// GameWorld only.

import Foundation
import GameEngine

/// One seated player in an Omaha session: a persistent chip count and a status.
public struct OmahaSessionPlayer: Equatable, Sendable {
    public let id: Int
    public internal(set) var chips: Int
    public internal(set) var status: PlayerStatus
    public let position: Int

    public init(id: Int, chips: Int, status: PlayerStatus = .active, position: Int) {
        self.id = id
        self.chips = chips
        self.status = status
        self.position = position
    }
}

/// Binds a player to a physical seat position and an action provider (bot or human).
public struct OmahaSeatAssignment {
    public let position: Int
    public let playerID: Int
    public let chips: Int
    public let provider: OmahaActionProvider

    public init(position: Int, playerID: Int, chips: Int, provider: OmahaActionProvider) {
        self.position = position
        self.playerID = playerID
        self.chips = chips
        self.provider = provider
    }
}

/// The outcome of one played Omaha hand.
public struct OmahaHandOutcome: Sendable {
    public let handNumber: Int
    public let buttonPosition: Int
    public let participantIDs: [Int]
    public let result: OmahaResult
    /// The (possibly escalated) blinds this hand was played at (D-064).
    public let smallBlind: Int
    public let bigBlind: Int
    /// The escalation level in force this hand (0 = base stakes).
    public let escalationLevel: Int
    public let bustedThisHand: [Int]
    public let chipsByPlayer: [Int: Int]
}

/// Why a session action failed. Same shape as the Texas/Draw session errors.
public enum OmahaSessionError: Error, Equatable, Sendable {
    case notEnoughPlayers
    case handInProgress
    case sessionEnded
    case positionOutOfRange(Int)
    case positionOccupied(Int)
    case duplicatePlayerID(Int)
    case nonPositiveChips
    case unknownPlayer(Int)
}
