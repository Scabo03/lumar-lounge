// ActionProvider.swift
// =====================================================================
// How the session driver asks "what do you do?" — uniformly, whether the
// answer comes from a bot or from a human (D-013).
//
// The driver builds a redacted `BotContext` (GameEngine's honest, seat-relative
// view) and awaits an `Action`. It does not know or care who produces it:
//   - a bot answers synchronously behind the async facade;
//   - a human answers whenever the UI submits the action, suspending the driver
//     until then via a continuation.
//
// GameWorld only: imports GameEngine (its raison d'être), never UI/Audio.

import Foundation
import GameEngine

/// Anything that can supply the action for the seat on turn, asynchronously.
public protocol ActionProvider {
    /// Return one action permitted by `context.legal`. The driver defensively
    /// legalizes the result, but well-behaved providers should already comply.
    func provideAction(for context: BotContext) async -> Action
}

/// Wraps a `PokerBot` (M1.3) as an action provider. The async facade resolves
/// immediately — a bot decides synchronously and deterministically.
public struct BotActionProvider: ActionProvider {
    public let bot: PokerBot

    public init(_ bot: PokerBot) { self.bot = bot }

    public func provideAction(for context: BotContext) async -> Action {
        bot.decide(context)
    }
}

/// A provider driven by a human: `provideAction` suspends until the UI calls
/// `submit(_:)`. Modelled as an actor so the continuation is handled safely
/// without any real threading of our own — just Swift Concurrency.
public actor HumanActionProvider: ActionProvider {
    private var continuation: CheckedContinuation<Action, Never>?
    /// The situation the human is currently being asked about (nil when idle).
    public private(set) var pendingContext: BotContext?

    public init() {}

    public func provideAction(for context: BotContext) async -> Action {
        await withCheckedContinuation { (continuation: CheckedContinuation<Action, Never>) in
            self.pendingContext = context
            self.continuation = continuation
        }
    }

    /// Delivers the human's chosen action, resuming the suspended driver.
    /// A no-op if nobody is currently waiting.
    public func submit(_ action: Action) {
        guard let continuation else { return }
        self.continuation = nil
        self.pendingContext = nil
        continuation.resume(returning: action)
    }

    /// Whether the driver is currently suspended waiting for this human.
    public var isWaiting: Bool { continuation != nil }
}
