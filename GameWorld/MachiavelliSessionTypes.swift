// MachiavelliSessionTypes.swift
// =====================================================================
// The session-level value types for a Machiavelli game: the seated player, the seat
// assignment binding a player to a turn provider, the game outcome, and the session
// errors. Parallel to the poker session types (the drivers never share rule-bearing
// types, D-038/D-042) but reusing the game-agnostic `PlayerStatus`.
//
// A Machiavelli SESSION plays a MATCH (partita): a SEQUENCE of HANDS (mani), scoring
// each hand (D-071) and ending when a player crosses the victory threshold — exactly
// as the poker session driver runs a sequence of hands (D-071). Who and how many
// opponents sit down is decided ABOVE the driver by the progressive matchmaker
// (`MachiavelliMatchmaker`), keyed on games played — never on time (D-064/D-070).
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

/// The outcome of one completed HAND (a single deal to a player going out, or a
/// stalemate). Scoring lives in the engine (`MachiavelliScoring`, D-071); this carries
/// the result.
public struct MachiavelliHandOutcome: Sendable {
    public let handNumber: Int
    /// The player who went out this hand, or `nil` if the hand was a stalemate.
    public let wentOutID: Int?
    /// Number of full turns taken this hand.
    public let turnsPlayed: Int
    /// Points earned THIS hand by player id (may be negative).
    public let handScores: [Int: Int]
    /// Cumulative match totals by player id, AFTER this hand.
    public let cumulativeScores: [Int: Int]
    /// Final hand counts by player id at hand end.
    public let handCounts: [Int: Int]
}

/// The outcome of a completed MATCH: a player crossed the victory threshold (D-071).
public struct MachiavelliMatchOutcome: Sendable {
    /// The player who crossed the threshold first (highest total on a tie-break by id).
    public let winnerID: Int
    /// How many hands the match took.
    public let handsPlayed: Int
    /// The final cumulative scores by player id.
    public let finalScores: [Int: Int]
}

/// Why a session action failed. Same shape as the poker session errors.
public enum MachiavelliSessionError: Error, Equatable, Sendable {
    case notEnoughPlayers
    case handInProgress
    case sessionEnded
    case matchAlreadyOver
    case positionOutOfRange(Int)
    case positionOccupied(Int)
    case duplicatePlayerID(Int)
    case unknownPlayer(Int)
}
