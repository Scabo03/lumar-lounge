// StudActionProvider.swift
// =====================================================================
// The uniform async facade through which the Stud driver asks a seat for its action,
// whether that seat is a bot (answers synchronously behind the facade) or a human
// (suspends on a continuation until the UI submits). Mirrors the other games' providers
// (D-013). The driver stays oblivious to which kind it is talking to.
//
// GameWorld only.

import Foundation
import GameEngine

/// A source of Stud actions for a seat, asked via an async call.
public protocol StudActionProvider {
    /// Provide a (legal) action for the redacted decision context.
    func provideAction(for context: StudBotContext) async -> StudAction
}

/// Wraps a `StudBot` so it satisfies the async provider facade synchronously.
public struct StudBotActionProvider: StudActionProvider {
    public let bot: StudBot
    public init(_ bot: StudBot) { self.bot = bot }
    public func provideAction(for context: StudBotContext) async -> StudAction { bot.decide(context) }
}

/// A human provider: `provideAction` suspends until the UI calls `submit(_:)`.
public actor HumanStudActionProvider: StudActionProvider {
    private var continuation: CheckedContinuation<StudAction, Never>?
    public private(set) var pendingContext: StudBotContext?

    public init() {}

    public func provideAction(for context: StudBotContext) async -> StudAction {
        await withCheckedContinuation { cont in
            self.pendingContext = context
            self.continuation = cont
        }
    }

    /// The UI submits the human's chosen action, resuming the suspended driver.
    public func submit(_ action: StudAction) {
        guard let cont = continuation else { return }
        continuation = nil
        pendingContext = nil
        cont.resume(returning: action)
    }

    public var isWaiting: Bool { continuation != nil }
}
