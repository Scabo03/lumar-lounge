// DrawActionProvider.swift
// =====================================================================
// How the Five-Card Draw session driver asks a seat "what do you do?" — and,
// separately, "which cards do you exchange?". Uniform across bots and humans, the
// draw analogue of the Texas `ActionProvider` (D-013), but with TWO distinct
// suspension points because a draw hand has two kinds of decision (D-042):
//   1. a betting action (fold/check/call/bet/raise) in each betting round;
//   2. a card exchange (0–4 discards) in the draw phase.
//
// GameWorld only: imports GameEngine (its raison d'être), never UI/Audio.

import Foundation
import GameEngine

/// Anything that can answer for a seat at a draw table: a betting action and a
/// draw exchange, both asynchronously.
public protocol DrawActionProvider {
    /// Return one action permitted by `context.legal`. The driver defensively
    /// legalizes the result.
    func provideAction(for context: DrawBotContext) async -> DrawAction
    /// Return the cards (0–4, a subset of the seat's hand) to discard in the draw.
    /// The driver validates the result and clamps it to a legal exchange.
    func provideDiscards(for context: DrawDrawContext) async -> [Card]
}

/// Wraps a `DrawBot` (GameEngine) as an action provider. The async facade resolves
/// immediately — a bot decides synchronously and deterministically.
public struct DrawBotActionProvider: DrawActionProvider {
    public let bot: DrawBot

    public init(_ bot: DrawBot) { self.bot = bot }

    public func provideAction(for context: DrawBotContext) async -> DrawAction {
        bot.decideAction(context)
    }
    public func provideDiscards(for context: DrawDrawContext) async -> [Card] {
        bot.decideDiscards(context)
    }
}

/// A provider driven by a human at a draw table. It has TWO cleanly separated
/// suspensions: `provideAction` waits for `submitAction`, `provideDiscards` waits
/// for `submitDiscards`. Only one is ever pending at a time (a hand asks for a
/// bet OR a draw, never both), so the UI reads whichever context is non-nil to
/// know what to present. Modelled as an actor for safe continuation handling.
public actor HumanDrawActionProvider: DrawActionProvider {
    private var actionContinuation: CheckedContinuation<DrawAction, Never>?
    private var drawContinuation: CheckedContinuation<[Card], Never>?

    /// The betting situation the human is being asked about (nil when not betting).
    public private(set) var pendingAction: DrawBotContext?
    /// The draw situation the human is being asked about (nil when not drawing).
    public private(set) var pendingDraw: DrawDrawContext?
    /// Set once the player has walked away from the table mid-hand (D-086).
    private var abandoned = false

    public init() {}

    public func provideAction(for context: DrawBotContext) async -> DrawAction {
        // ABANDONED (D-086): fold now and for every turn still to come.
        if abandoned { return .fold }
        return await withCheckedContinuation { (cont: CheckedContinuation<DrawAction, Never>) in
            self.pendingAction = context
            self.actionContinuation = cont
        }
    }

    public func provideDiscards(for context: DrawDrawContext) async -> [Card] {
        // ABANDONED (D-086): stand pat — the seat has folded, the exchange is moot.
        if abandoned { return [] }
        return await withCheckedContinuation { (cont: CheckedContinuation<[Card], Never>) in
            self.pendingDraw = context
            self.drawContinuation = cont
        }
    }

    /// The player has left the table: fold (and stand pat) now and for the rest of
    /// the hand, so BOTH suspensions release and the driver can finish (D-086).
    public func abandon() {
        abandoned = true
        if let cont = actionContinuation {
            actionContinuation = nil; pendingAction = nil
            cont.resume(returning: .fold)
        }
        if let cont = drawContinuation {
            drawContinuation = nil; pendingDraw = nil
            cont.resume(returning: [])
        }
    }

    /// Delivers the human's betting action, resuming the suspended driver.
    public func submitAction(_ action: DrawAction) {
        guard let cont = actionContinuation else { return }
        actionContinuation = nil
        pendingAction = nil
        cont.resume(returning: action)
    }

    /// Delivers the human's chosen discards, resuming the suspended driver.
    public func submitDiscards(_ cards: [Card]) {
        guard let cont = drawContinuation else { return }
        drawContinuation = nil
        pendingDraw = nil
        cont.resume(returning: cards)
    }

    /// Whether the driver is suspended waiting for a betting action.
    public var isWaitingForAction: Bool { actionContinuation != nil }
    /// Whether the driver is suspended waiting for a draw exchange.
    public var isWaitingForDraw: Bool { drawContinuation != nil }
}
