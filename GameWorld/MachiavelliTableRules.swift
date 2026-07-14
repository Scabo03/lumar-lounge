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
    public let victoryThreshold: Int

    public init(buyIn: Int, handSize: Int = MachiavelliConstants.handSize,
                victoryThreshold: Int = MachiavelliSessionDriver.defaultVictoryThreshold) {
        self.buyIn = buyIn
        self.handSize = handSize
        self.victoryThreshold = victoryThreshold
    }

    /// The ClockTower's Machiavelli table: a LOW buy-in (1200, just above the Riverwood's
    /// 1000 — the cheapest entry of any speciality) that is fully refunded on leaving,
    /// because at the ClockTower you play for vanity, not money (D-072). Standard 13-card
    /// hands, the calibrated ~3-hand match threshold (D-071).
    public static let clockTower = MachiavelliTableRules(buyIn: 1200)
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
