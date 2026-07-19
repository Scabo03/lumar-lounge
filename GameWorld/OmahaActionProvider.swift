// OmahaActionProvider.swift
// =====================================================================
// The uniform async facade through which the Omaha driver asks a seat for its
// action, whether that seat is a bot (answers synchronously behind the facade) or a
// human (suspends on a continuation until the UI submits). Mirrors the Texas
// `ActionProvider` and Draw `DrawActionProvider` (D-013). The driver stays oblivious
// to which kind it is talking to.
//
// GameWorld only.

import Foundation
import GameEngine

/// A source of Omaha actions for a seat, asked via an async call.
public protocol OmahaActionProvider {
    /// Provide a (legal) action for the redacted decision context.
    func provideAction(for context: OmahaBotContext) async -> OmahaAction
}

/// Wraps an `OmahaBot` so it satisfies the async provider facade synchronously.
public struct OmahaBotActionProvider: OmahaActionProvider {
    public let bot: OmahaBot
    public init(_ bot: OmahaBot) { self.bot = bot }
    public func provideAction(for context: OmahaBotContext) async -> OmahaAction { bot.decide(context) }
}

/// A human provider: `provideAction` suspends until the UI calls `submit(_:)`. There
/// is no Omaha UI yet (engine-only brick), but the provider exists so the driver's
/// action interface is uniform and a future UI plugs straight in (D-013).
public actor HumanOmahaActionProvider: OmahaActionProvider {
    private var continuation: CheckedContinuation<OmahaAction, Never>?
    /// Set once the player has walked away from the table mid-hand (D-086).
    private var abandoned = false
    public private(set) var pendingContext: OmahaBotContext?

    public init() {}

    public func provideAction(for context: OmahaBotContext) async -> OmahaAction {
        // ABANDONED (D-086): the player left mid-hand — fold now and for every turn
        // still to come, so the driver finishes the hand at code speed.
        if abandoned { return .fold }
        return await withCheckedContinuation { cont in
            self.pendingContext = context
            self.continuation = cont
        }
    }

    /// The UI submits the human's chosen action, resuming the suspended driver.
    public func submit(_ action: OmahaAction) {
        guard let cont = continuation else { return }
        continuation = nil
        pendingContext = nil
        cont.resume(returning: action)
    }

    /// The player has left the table: fold now and for the rest of the hand.
    public func abandon() {
        abandoned = true
        guard let cont = continuation else { return }
        continuation = nil
        pendingContext = nil
        cont.resume(returning: .fold)
    }

    public var isWaiting: Bool { continuation != nil }
}
