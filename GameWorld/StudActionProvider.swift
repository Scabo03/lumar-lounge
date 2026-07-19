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
    /// Set once the player has walked away from the table mid-hand (D-086).
    private var abandoned = false
    public private(set) var pendingContext: StudBotContext?

    public init() {}

    public func provideAction(for context: StudBotContext) async -> StudAction {
        // ABANDONED (D-086): the player left mid-hand — fold now and for every turn
        // still to come, so the driver finishes the hand at code speed.
        if abandoned { return .fold }
        return await withCheckedContinuation { cont in
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
