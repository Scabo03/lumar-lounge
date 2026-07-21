// RouletteActionProvider.swift
// =====================================================================
// How the driver asks the player for their bets (D-102).
//
// Roulette suspends ONCE per round: the player composes a slip of bets and
// confirms. There are no bots (the player is alone against chance), so there is
// only the human provider and a scripted one for tests.

import Foundation
import GameEngine

/// What the player needs to know while composing bets.
public struct RouletteBetContext: Equatable, Sendable {
    public let chips: Int
    public let minimumBet: Int
    public let maximumBet: Int

    public init(chips: Int, minimumBet: Int, maximumBet: Int) {
        self.chips = chips
        self.minimumBet = minimumBet
        self.maximumBet = maximumBet
    }
}

public protocol RouletteActionProvider {
    /// The confirmed bets for the next spin (bet → fiches), or nil to stop playing.
    func provideBets(for context: RouletteBetContext) async -> [RouletteBet: Int]?
}

/// The human at the table: suspends until the interface confirms a slip.
public actor HumanRouletteActionProvider: RouletteActionProvider {

    private var continuation: CheckedContinuation<[RouletteBet: Int]?, Never>?
    private var abandoned = false

    public private(set) var pending: RouletteBetContext?

    public init() {}

    public func provideBets(for context: RouletteBetContext) async -> [RouletteBet: Int]? {
        if abandoned { return nil }
        return await withCheckedContinuation { continuation in
            self.pending = context
            self.continuation = continuation
        }
    }

    public func submit(_ bets: [RouletteBet: Int]) {
        guard let continuation else { return }
        self.continuation = nil
        self.pending = nil
        continuation.resume(returning: bets)
    }

    /// Leaving the table (D-086): resume whatever is suspended right now with nil, and
    /// answer every later request without suspending, so the driver winds up at once.
    public func abandon() {
        abandoned = true
        if let continuation {
            self.continuation = nil
            self.pending = nil
            continuation.resume(returning: nil)
        }
    }
}

/// A scripted provider for tests: plays a fixed list of slips, then stops.
public actor ScriptedRouletteActionProvider: RouletteActionProvider {
    private var slips: [[RouletteBet: Int]]
    public init(_ slips: [[RouletteBet: Int]]) { self.slips = slips }
    public func provideBets(for context: RouletteBetContext) async -> [RouletteBet: Int]? {
        guard !slips.isEmpty else { return nil }
        return slips.removeFirst()
    }
}
