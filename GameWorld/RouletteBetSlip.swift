// RouletteBetSlip.swift
// =====================================================================
// THE SINGLE SOURCE OF TRUTH for the bets a player is composing (D-102).
//
// The roulette table has two zones that both act on the bets: the selection
// table (touch a cell to place, swipe to adjust) and the register band (a
// compact list of the active bets, each symbol also operable). The imposed
// architectural constraint is that these are TWO INTERFACES ON ONE STATE, never
// two implementations — placing or adjusting "red" from the table or from its
// symbol in the band must be the identical operation on the identical entry.
// That state is this slip: a map from a bet to the fiches on it. Both zones hold
// the same slip and call the same methods, so there is no way for the two to
// diverge. It is the same discipline the Machiavelli box and drag share by
// interrogating one predicate (D-070).
//
// Pure and testable: no SwiftUI, no chips ledger (the driver owns the wallet).
// Amounts are always whole multiples of the table minimum, so a touch IS the
// minimum bet and a swipe steps by the minimum.

import Foundation
import GameEngine

public struct RouletteBetSlip: Equatable, Sendable {

    /// The table minimum: the amount a touch places, and the step of a swipe.
    public let minimumBet: Int
    /// The most that may sit on any single bet.
    public let maximumBet: Int

    /// The active bets — bet → fiches on it. A bet not present carries nothing.
    public private(set) var bets: [RouletteBet: Int]

    public init(minimumBet: Int, maximumBet: Int, bets: [RouletteBet: Int] = [:]) {
        self.minimumBet = max(1, minimumBet)
        self.maximumBet = max(self.minimumBet, maximumBet)
        self.bets = bets
    }

    /// Everything currently at stake — the number the register band shows and the
    /// player can always interrogate before confirming (D-102).
    public var totalStaked: Int { bets.values.reduce(0, +) }

    /// The active bets in navigation-frequency order, so the band reads the most
    /// common first, exactly as the table does (D-101/D-102).
    public var orderedBets: [(bet: RouletteBet, amount: Int)] {
        bets.sorted { a, b in
            if a.key.frequencyRank != b.key.frequencyRank { return a.key.frequencyRank < b.key.frequencyRank }
            if a.key.covered != b.key.covered { return a.key.covered.lexicographicallyPrecedes(b.key.covered) }
            return a.key.kind.rawValue < b.key.kind.rawValue
        }.map { (bet: $0.key, amount: $0.value) }
    }

    public func amount(on bet: RouletteBet) -> Int { bets[bet] ?? 0 }
    public func contains(_ bet: RouletteBet) -> Bool { bets[bet] != nil }

    // MARK: - Operations (identical whichever zone calls them)

    /// A touch: place the minimum on a bet that has nothing, otherwise leave it be.
    /// (Touching again does not stack — the swipe is how the player raises it, so a
    /// stray double-tap never surprises them.)
    public mutating func place(_ bet: RouletteBet) {
        guard bets[bet] == nil else { return }
        bets[bet] = minimumBet
    }

    /// One swipe up: add a minimum's worth, up to the ceiling. Placing it if absent.
    public mutating func increase(_ bet: RouletteBet) {
        let current = bets[bet] ?? 0
        bets[bet] = min(maximumBet, ((current / minimumBet) + 1) * minimumBet)
    }

    /// One swipe down: remove a minimum's worth. Reaching zero REMOVES the bet — the
    /// symbol's way of being cancelled (D-102).
    public mutating func decrease(_ bet: RouletteBet) {
        let current = bets[bet] ?? 0
        let next = ((current / minimumBet) - 1) * minimumBet
        if next <= 0 { bets[bet] = nil } else { bets[bet] = next }
    }

    /// Set an exact amount, clamped to a whole multiple of the minimum inside the band;
    /// zero (or less) removes the bet.
    public mutating func setAmount(_ amount: Int, on bet: RouletteBet) {
        let stepped = (amount / minimumBet) * minimumBet
        if stepped <= 0 { bets[bet] = nil } else { bets[bet] = min(maximumBet, stepped) }
    }

    /// Remove a bet outright (a symbol zeroed to nothing).
    public mutating func remove(_ bet: RouletteBet) { bets[bet] = nil }

    /// Clear the whole slip (a new round, or "start over").
    public mutating func clear() { bets.removeAll() }
}
