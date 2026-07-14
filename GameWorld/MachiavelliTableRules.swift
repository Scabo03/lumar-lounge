// MachiavelliTableRules.swift
// =====================================================================
// A Machiavelli table's configuration (D-072): the fixed table parameters — buy-in,
// hand size and the match victory threshold (D-071). Unlike the poker tables, it does
// NOT carry a fixed roster: a Machiavelli game seats ONE or TWO opponents chosen by the
// progressive matchmaker (`MachiavelliMatchmaker`) from the games-played counter
// (D-070), so who sits down is decided at session start, not baked into the rules.
//
// The ClockTower's Machiavelli is the project's MOST ACCESSIBLE table economically
// (D-072): you play for prestige, not money, so the buy-in is LOW (barely above the
// Riverwood) and fully REFUNDED when you leave (no fiches are ever wagered). One table
// so far: the ClockTower's Machiavelli.
//
// GameWorld only.

import Foundation
import GameEngine

public struct MachiavelliTableRules: Equatable, Sendable {
    public let buyIn: Int
    public let handSize: Int

    public init(buyIn: Int, handSize: Int = MachiavelliConstants.handSize) {
        self.buyIn = buyIn
        self.handSize = handSize
    }

    /// The ClockTower's Machiavelli table: a LOW buy-in (1200, just above the Riverwood's
    /// 1000 — the cheapest entry of any speciality). A single hand decides the game
    /// (D-075); a loser recovers a share of the buy-in by how well they played (the refund
    /// economy, `MachiavelliRefund`) — at the ClockTower you play for vanity, not money,
    /// and how you played matters more than the outcome (D-072/D-075). Standard 13 cards.
    public static let clockTower = MachiavelliTableRules(buyIn: 1200)
}

// MARK: - The refund economy (D-075)

/// Turns a losing player's final SCORE into a partial buy-in REFUND — the second life of
/// the Machiavelli scoring (D-071→D-075): no longer a threshold to cross over many hands,
/// but a measure of how well a loser played, giving purpose to a losing hand WITHOUT
/// adding a single turn. It is a SESSION/ECONOMY mechanic, so it lives in GameWorld.
///
/// Whoever GOES OUT wins and keeps their full buy-in (the win is the reward — at the
/// ClockTower you play for prestige, not money, D-072). A LOSER recovers a fraction of
/// their buy-in: up to ~20% for someone who played well and lost narrowly, sliding to 0
/// for someone who laid almost nothing and sat on a near-intact hand — if even that were
/// refunded, the mechanic would punish nothing and be pointless (D-075). The economy is
/// the FIRST in the project where a table's money EXPRESSES the casino's character rather
/// than just scaling numbers: the refund is a gesture of regard for good play, not a
/// parachute that annuls the loss.
public enum MachiavelliRefund {

    /// No refund at or below this score — laid almost nothing / stuck on a heavy hand.
    public static let scoreFloor = 20
    /// Full (maximum) refund at or above this score — played well, lost narrowly. Chosen
    /// just under a hand-winner's ~100 (measured, D-071), so a strong loser reaches the top.
    public static let scoreCeiling = 90
    /// The maximum share of the buy-in a loser can recover.
    public static let maxFraction = 0.20

    /// The refund fraction (0…`maxFraction`) for a loser's final score — linear between the
    /// floor and the ceiling.
    public static func refundFraction(score: Int) -> Double {
        guard score > scoreFloor else { return 0 }
        guard score < scoreCeiling else { return maxFraction }
        return Double(score - scoreFloor) / Double(scoreCeiling - scoreFloor) * maxFraction
    }

    /// The chips a loser recovers from a buy-in given their final score (rounded).
    public static func refund(score: Int, buyIn: Int) -> Int {
        Int((refundFraction(score: score) * Double(buyIn)).rounded())
    }

    /// The chips a player cashes out at game end: the FULL buy-in if they won (D-072), else
    /// the score-based refund (D-075).
    public static func cashOut(won: Bool, score: Int, buyIn: Int) -> Int {
        won ? buyIn : refund(score: score, buyIn: buyIn)
    }
}

// MARK: - Progressive-encounter persistence (D-070)

/// Where the Machiavelli "games played" counter is stored between launches. It drives
/// the progressive matchmaker so the player meets the student first and the professor
/// only after a career (D-070). Keyed on games PLAYED, never on time.
public protocol MachiavelliProgressStore {
    func loadGamesPlayed() -> Int
    func saveGamesPlayed(_ count: Int)
}

/// A non-persistent store (tests, previews): starts at zero (or an injected value).
public final class InMemoryMachiavelliProgress: MachiavelliProgressStore {
    private var value: Int
    public init(gamesPlayed: Int = 0) { value = gamesPlayed }
    public func loadGamesPlayed() -> Int { value }
    public func saveGamesPlayed(_ count: Int) { value = count }
}

/// The default store, backed by UserDefaults.
public struct UserDefaultsMachiavelliProgress: MachiavelliProgressStore {
    private let defaults: UserDefaults
    private let key = "lumar.machiavelli.gamesPlayed"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func loadGamesPlayed() -> Int { defaults.integer(forKey: key) }
    public func saveGamesPlayed(_ count: Int) { defaults.set(count, forKey: key) }
}
