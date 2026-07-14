// StudSessionTypes.swift
// =====================================================================
// The session-level value types for a Seven-Card Stud table: the seated player, the
// seat assignment binding a player to an action provider, the per-hand outcome, and the
// session errors. Parallel to the Texas/Draw/Omaha equivalents — the drivers never share
// rule-bearing types (D-077) — reusing only the game-agnostic `PlayerStatus`.
//
// GameWorld only.

import Foundation
import GameEngine

/// One seated player in a Stud session: a persistent chip count and a status.
public struct StudSessionPlayer: Equatable, Sendable {
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
public struct StudSeatAssignment {
    public let position: Int
    public let playerID: Int
    public let chips: Int
    public let provider: StudActionProvider

    public init(position: Int, playerID: Int, chips: Int, provider: StudActionProvider) {
        self.position = position
        self.playerID = playerID
        self.chips = chips
        self.provider = provider
    }
}

/// The outcome of one played Stud hand.
public struct StudHandOutcome: Sendable {
    public let handNumber: Int
    public let participantIDs: [Int]
    public let result: StudResult
    public let ante: Int
    public let bringIn: Int
    public let bet: Int
    /// The escalation level in force this hand (0 = base stakes).
    public let escalationLevel: Int
    /// The house prize the player was awarded this hand (0 if they didn't win, D-078).
    public let housePrizeAwarded: Int
    public let bustedThisHand: [Int]
    public let chipsByPlayer: [Int: Int]
}

/// Why a session action failed. Same shape as the other session errors.
public enum StudSessionError: Error, Equatable, Sendable {
    case notEnoughPlayers
    case handInProgress
    case sessionEnded
    case positionOutOfRange(Int)
    case positionOccupied(Int)
    case duplicatePlayerID(Int)
    case nonPositiveChips
    case unknownPlayer(Int)
}
