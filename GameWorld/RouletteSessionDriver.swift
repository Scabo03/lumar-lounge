// RouletteSessionDriver.swift
// =====================================================================
// Runs a roulette session: bet, spin, settle, pay, again (D-102).
//
// A pure client of the engine — it never reaches inside the resolver, only
// calls its public surface. It owns what a SESSION owns and a spin does not: the
// player's fiches, the wheel carried from spin to spin, the limits, and the
// narration. The producer runs at code speed and knows nothing of the human
// rhythm; pacing lives entirely in the consumer (D-018).
//
// Determinism follows the blackjack shape, not the poker one (D-090): the wheel
// PERSISTS across the session, so it is seeded once — fixed in tests, a fresh
// system seed in production (every session and every spin different, D-047).

import Foundation
import GameEngine

public struct RouletteRoundOutcome: Sendable {
    public let roundNumber: Int
    public let resolution: RouletteRoundResolution
    public let chipsAfter: Int
    public var net: Int { resolution.net }
}

public enum RouletteSessionError: Error, Equatable, Sendable {
    case sessionEnded
    case roundInProgress
    case notEnoughChips
}

public final class RouletteSessionDriver {

    // MARK: Configuration
    public let minimumBet: Int
    public let maximumBet: Int

    private let provider: RouletteActionProvider
    private let hub = RouletteEventHub()

    // MARK: State
    public private(set) var chips: Int
    public private(set) var roundNumber = 0
    public private(set) var isRoundInProgress = false
    public private(set) var hasEnded = false

    private var wheel: RouletteWheel
    private var sessionAnnounced = false

    public init(chips: Int, rules: RouletteTableRules,
                provider: RouletteActionProvider, seed: UInt64? = nil) {
        self.chips = chips
        self.minimumBet = rules.minimumBet
        self.maximumBet = rules.maximumBet
        self.provider = provider
        self.wheel = RouletteWheel(seed: seed ?? UInt64.random(in: .min ... .max))
    }

    // MARK: Queries
    public var canSpinAgain: Bool { !hasEnded && !isRoundInProgress && chips >= minimumBet }

    public func events(as viewer: EventViewer = .spectator) async -> AsyncStream<RouletteSessionEvent> {
        await hub.subscribe(as: viewer)
    }

    // MARK: Playing

    /// Plays one round: collect bets, spin, settle, pay.
    /// - Returns: the settled round, or `nil` when the player declined to bet
    ///   (which is how leaving the table arrives here).
    @discardableResult
    public func playRound() async throws -> RouletteRoundOutcome? {
        guard !hasEnded else { throw RouletteSessionError.sessionEnded }
        guard !isRoundInProgress else { throw RouletteSessionError.roundInProgress }
        guard chips >= minimumBet else { throw RouletteSessionError.notEnoughChips }

        isRoundInProgress = true
        defer { isRoundInProgress = false }

        await announceSessionIfNeeded()

        let context = RouletteBetContext(chips: chips, minimumBet: minimumBet, maximumBet: maximumBet)
        guard let requested = await provider.provideBets(for: context) else { return nil }

        // The driver never trusts a provider: sanitize the slip to what is actually
        // affordable and legal, so the session stays total even with a bad provider
        // (D-013). Bets are dropped, never partially honoured, if the total exceeds
        // the wallet — cheapest first, so the player keeps as much of their intent as
        // fits (this cannot happen through the real UI, which caps at the wallet).
        let bets = affordable(requested)
        guard !bets.isEmpty else { return nil }
        let staked = bets.values.reduce(0, +)

        chips -= staked
        roundNumber += 1
        await hub.emit(.roundBegan(roundNumber: roundNumber, totalStaked: staked, chips: chips))

        let pocket = wheel.spin()
        await hub.emit(.wheelSpun(pocket: pocket, color: RouletteLayout.color(of: pocket)))

        let resolution = RouletteResolver.resolve(bets: bets, pocket: pocket)
        chips += resolution.totalReturned
        await hub.emit(.roundResolved(resolution: resolution, chips: chips))
        await hub.emit(.roundEnded(roundNumber: roundNumber, net: resolution.net, chips: chips))

        return RouletteRoundOutcome(roundNumber: roundNumber, resolution: resolution, chipsAfter: chips)
    }

    @discardableResult
    public func run(maxRounds: Int = .max) async throws -> [RouletteRoundOutcome] {
        var outcomes: [RouletteRoundOutcome] = []
        while outcomes.count < maxRounds, canSpinAgain {
            guard let outcome = try await playRound() else { break }
            outcomes.append(outcome)
        }
        return outcomes
    }

    public func endSession(reason: RouletteSessionEndReason = .stopped) async {
        guard !hasEnded else { return }
        hasEnded = true
        await announceSessionIfNeeded()
        await hub.emit(.sessionEnded(reason: reason))
        await hub.finishAll()
    }

    // MARK: - Helpers

    private func announceSessionIfNeeded() async {
        guard !sessionAnnounced else { return }
        sessionAnnounced = true
        await hub.emit(.sessionBegan(chips: chips, minimumBet: minimumBet, maximumBet: maximumBet))
    }

    /// Clamps each bet into the legal per-bet band and drops bets, cheapest first, until
    /// the total fits the wallet.
    private func affordable(_ requested: [RouletteBet: Int]) -> [RouletteBet: Int] {
        var clamped: [RouletteBet: Int] = [:]
        for (bet, amount) in requested {
            let stepped = (amount / minimumBet) * minimumBet
            let value = min(maximumBet, max(minimumBet, stepped))
            if amount >= minimumBet { clamped[bet] = value }
        }
        var total = clamped.values.reduce(0, +)
        while total > chips, let cheapest = clamped.min(by: { $0.value < $1.value })?.key {
            total -= clamped[cheapest] ?? 0
            clamped[cheapest] = nil
        }
        return clamped
    }
}
