// MachiavelliTurnProvider.swift
// =====================================================================
// The uniform async facade through which the Machiavelli driver asks a seat for its
// whole-turn plan, whether that seat is a bot (answers synchronously behind the facade)
// or a human (suspends on a continuation until the future UI submits). Mirrors the
// poker action providers (D-013); the driver stays oblivious to which kind it talks to.
//
// A Machiavelli turn is a SEQUENCE of transformations closed by a terminal, so the unit
// exchanged is a `MachiavelliTurnPlan`, not a single action. There is no Machiavelli UI
// yet (engine-only brick), but the human provider exists so the interface is uniform
// and a future UI plugs straight in. GameWorld only.

import Foundation
import GameEngine

/// A source of Machiavelli turn plans for a seat, asked via an async call.
public protocol MachiavelliTurnProvider {
    /// Provide a turn plan for the redacted decision context.
    func provideTurn(for context: MachiavelliBotContext) async -> MachiavelliTurnPlan
    /// The expected deliberation for this provider (a descriptive hint the driver
    /// forwards for the audible-wait event). Bots return their personality's cap; a
    /// human returns zero.
    var expectedDeliberation: Duration { get }
    /// Whether this provider is a bot (the driver brackets bot turns with thinking
    /// events; a human turn is paced by the UI, not the engine).
    var isBot: Bool { get }
}

public extension MachiavelliTurnProvider {
    var expectedDeliberation: Duration { .zero }
    var isBot: Bool { false }
}

/// Wraps a `MachiavelliBot` so it satisfies the async provider facade synchronously.
public struct MachiavelliBotTurnProvider: MachiavelliTurnProvider {
    public let bot: HeuristicMachiavelliBot
    public init(_ bot: HeuristicMachiavelliBot) { self.bot = bot }
    public func provideTurn(for context: MachiavelliBotContext) async -> MachiavelliTurnPlan {
        bot.planTurn(context)
    }
    public var expectedDeliberation: Duration { bot.expectedDeliberation }
    public var isBot: Bool { true }
}

/// A human provider: `provideTurn` suspends until the UI calls `submit(_:)`.
public actor HumanMachiavelliTurnProvider: MachiavelliTurnProvider {
    private var continuation: CheckedContinuation<MachiavelliTurnPlan, Never>?
    public private(set) var pendingContext: MachiavelliBotContext?
    /// Set once the player has walked away from the table mid-match (D-086).
    private var abandoned = false

    public init() {}

    public func provideTurn(for context: MachiavelliBotContext) async -> MachiavelliTurnPlan {
        // ABANDONED (D-086): the player walked away. Every remaining turn of theirs
        // places nothing and draws, so the match resolves at code speed instead of
        // hanging on a human who has left. At Machiavelli the hand IS the match, so
        // without this the player would have had to sit through the whole thing.
        if abandoned { return MachiavelliTurnPlan(finalTable: context.table.map(\.cards), terminal: .draw) }
        return await withCheckedContinuation { cont in
            self.pendingContext = context
            self.continuation = cont
        }
    }

    /// The UI submits the human's chosen turn plan, resuming the suspended driver.
    public func submit(_ plan: MachiavelliTurnPlan) {
        guard let cont = continuation else { return }
        continuation = nil
        pendingContext = nil
        cont.resume(returning: plan)
    }

    /// The player has left the table: draw now and for every remaining turn.
    public func abandon() {
        abandoned = true
        guard let cont = continuation else { return }
        let table = (pendingContext?.table ?? []).map(\.cards)
        continuation = nil
        pendingContext = nil
        cont.resume(returning: MachiavelliTurnPlan(finalTable: table, terminal: .draw))
    }

    public var isWaiting: Bool { continuation != nil }
    nonisolated public var expectedDeliberation: Duration { .zero }
    nonisolated public var isBot: Bool { false }
}
