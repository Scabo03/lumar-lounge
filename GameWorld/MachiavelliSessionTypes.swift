// MachiavelliSessionTypes.swift
// =====================================================================
// The session-level value types for a Machiavelli game: the seated player, the seat
// assignment binding a player to a turn provider, the game outcome, and the session
// errors. Parallel to the poker session types (the drivers never share rule-bearing
// types, D-038/D-042) but reusing the game-agnostic `PlayerStatus`.
//
// A Machiavelli SESSION plays exactly one GAME to completion (deal → turns until a
// player empties their hand). Who and how many opponents sit down is decided ABOVE the
// driver by the progressive matchmaker (`MachiavelliMatchmaker`), keyed on games
// played — never on time (D-064/D-070).
//
// GameWorld only.

import Foundation
import GameEngine

/// One seated player in a Machiavelli game: an id, a hand size (chips do not exist
/// here — Machiavelli has no wagering), and a status.
public struct MachiavelliSessionPlayer: Equatable, Sendable {
    public let id: Int
    public internal(set) var handCount: Int
    public internal(set) var status: PlayerStatus
    public let position: Int

    public init(id: Int, handCount: Int, status: PlayerStatus = .active, position: Int) {
        self.id = id
        self.handCount = handCount
        self.status = status
        self.position = position
    }
}

/// Binds a player to a seat and a turn provider (bot or human).
public struct MachiavelliSeatAssignment {
    public let position: Int
    public let playerID: Int
    public let provider: MachiavelliTurnProvider

    public init(position: Int, playerID: Int, provider: MachiavelliTurnProvider) {
        self.position = position
        self.playerID = playerID
        self.provider = provider
    }
}

/// The outcome of one completed Machiavelli game.
public struct MachiavelliGameOutcome: Sendable {
    /// The player who emptied their hand first.
    public let winnerID: Int
    /// Number of full turns taken before the game ended.
    public let turnsPlayed: Int
    /// Final hand counts by player id (the winner is 0).
    public let handCounts: [Int: Int]
}

/// Why a session action failed. Same shape as the poker session errors.
public enum MachiavelliSessionError: Error, Equatable, Sendable {
    case notEnoughPlayers
    case gameInProgress
    case sessionEnded
    case gameAlreadyOver
    case positionOutOfRange(Int)
    case positionOccupied(Int)
    case duplicatePlayerID(Int)
    case unknownPlayer(Int)
}
