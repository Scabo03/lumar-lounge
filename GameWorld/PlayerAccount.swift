// PlayerAccount.swift
// =====================================================================
// The player's persistent CHIPS — the currency OUTSIDE the tables, distinct from
// the FICHES that live only at a table (D-036). Chips carry across sessions; a
// buy-in converts chips → table fiches, and standing up converts remaining fiches
// → chips. Chips belong to GameWorld; UI only displays them.
//
// Persistence is behind a small injectable protocol so the account is testable
// without touching real UserDefaults.

import Foundation

/// Where the player's chips are stored between launches.
public protocol ChipsStore {
    func loadChips() -> Int?
    func saveChips(_ chips: Int)
}

/// A non-persistent store (UI tests, previews): always starts fresh.
public final class InMemoryChipsStore: ChipsStore {
    private var value: Int?
    public init(chips: Int? = nil) { value = chips }
    public func loadChips() -> Int? { value }
    public func saveChips(_ chips: Int) { value = chips }
}

/// The default store, backed by UserDefaults.
public struct UserDefaultsChipsStore: ChipsStore {
    private let defaults: UserDefaults
    private let key = "lumar.player.chips"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func loadChips() -> Int? { defaults.object(forKey: key) as? Int }
    public func saveChips(_ chips: Int) { defaults.set(chips, forKey: key) }
}

/// The player's chip balance, persisted. First launch grants a starting stake.
public final class PlayerAccount {

    /// Chips granted on the very first launch.
    public static let startingChips = 5000

    public private(set) var chips: Int
    private let store: ChipsStore

    public init(store: ChipsStore = UserDefaultsChipsStore()) {
        self.store = store
        if let saved = store.loadChips() {
            self.chips = saved
        } else {
            self.chips = Self.startingChips
            store.saveChips(self.chips)   // persist the initial grant
        }
    }

    /// Whether the player can cover a buy-in.
    public func canAfford(_ buyIn: Int) -> Bool { chips >= buyIn }

    /// Takes a buy-in out of the account (chips → table fiches). Returns false and
    /// changes nothing if the player can't afford it.
    @discardableResult
    public func buyIn(_ amount: Int) -> Bool {
        guard amount >= 0, chips >= amount else { return false }
        chips -= amount
        store.saveChips(chips)
        return true
    }

    /// Returns remaining table fiches to the account (fiches → chips). A bust
    /// cashes out 0, so nothing is credited.
    public func cashOut(_ amount: Int) {
        guard amount > 0 else { return }
        chips += amount
        store.saveChips(chips)
    }
}
