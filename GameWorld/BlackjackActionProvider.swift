// BlackjackActionProvider.swift
// =====================================================================
// How the driver asks the player what to do.
//
// Blackjack suspends TWICE per round — once for the wager, once (or more,
// with splits) for a move — so the provider has two entry points, kept
// strictly separate as in the Draw (D-042): only one may be pending at a
// time.
//
// There are no bots at a blackjack table (the player faces the house alone),
// so there is no bot-backed provider here — only the human one and a scripted
// one for tests.

import Foundation
import GameEngine

/// The information the player needs to choose a wager.
public struct BlackjackBetContext: Equatable, Sendable {
    public let chips: Int
    public let minimumBet: Int
    public let maximumBet: Int
    public let lastBet: Int?

    public init(chips: Int, minimumBet: Int, maximumBet: Int, lastBet: Int?) {
        self.chips = chips
        self.minimumBet = minimumBet
        self.maximumBet = maximumBet
        self.lastBet = lastBet
    }
}

/// The information the player needs to choose a move — the state of the hand
/// in front of them, what is legal, and the dealer's up card.
///
/// This is DESCRIPTION only: no recommendation, no basic-strategy hint, no
/// "expected value". The system describes the state, it never advises the
/// move (D-091).
public struct BlackjackTurnContext: Equatable, Sendable {
    public let handIndex: Int
    public let handCount: Int
    public let cards: [Card]
    public let total: Int
    public let isSoft: Bool
    public let bet: Int
    public let dealerUpCard: Card
    public let chips: Int
    public let legal: BlackjackLegalActions

    public init(handIndex: Int, handCount: Int, cards: [Card], total: Int, isSoft: Bool,
                bet: Int, dealerUpCard: Card, chips: Int, legal: BlackjackLegalActions) {
        self.handIndex = handIndex
        self.handCount = handCount
        self.cards = cards
        self.total = total
        self.isSoft = isSoft
        self.bet = bet
        self.dealerUpCard = dealerUpCard
        self.chips = chips
        self.legal = legal
    }
}

public protocol BlackjackActionProvider {
    /// The wager for the next round, or nil to stop playing.
    func provideBet(for context: BlackjackBetContext) async -> Int?
    func provideAction(for context: BlackjackTurnContext) async -> BlackjackAction
}

/// The human at the table: suspends until the interface submits.
public actor HumanBlackjackActionProvider: BlackjackActionProvider {

    private var betContinuation: CheckedContinuation<Int?, Never>?
    private var actionContinuation: CheckedContinuation<BlackjackAction, Never>?
    private var abandoned = false

    public private(set) var pendingBet: BlackjackBetContext?
    public private(set) var pendingTurn: BlackjackTurnContext?

    public init() {}

    public func provideBet(for context: BlackjackBetContext) async -> Int? {
        if abandoned { return nil }
        return await withCheckedContinuation { continuation in
            self.pendingBet = context
            self.betContinuation = continuation
        }
    }

    public func provideAction(for context: BlackjackTurnContext) async -> BlackjackAction {
        // D-086: once the player has walked away, every remaining decision
        // resolves at code speed. Standing is the safe terminal answer — it
        // commits no further chips, unlike hitting.
        if abandoned { return .stand }
        return await withCheckedContinuation { continuation in
            self.pendingTurn = context
            self.actionContinuation = continuation
        }
    }

    public func submitBet(_ amount: Int) {
        guard let continuation = betContinuation else { return }
        betContinuation = nil
        pendingBet = nil
        continuation.resume(returning: amount)
    }

    public func submitAction(_ action: BlackjackAction) {
        guard let continuation = actionContinuation else { return }
        actionContinuation = nil
        pendingTurn = nil
        continuation.resume(returning: action)
    }

    /// Leaving the table (D-086): resume whatever is suspended right now, and
    /// answer every later question without suspending, so the driver can wind
    /// the session up immediately.
    public func abandon() {
        abandoned = true
        if let continuation = betContinuation {
            betContinuation = nil
            pendingBet = nil
            continuation.resume(returning: nil)
        }
        if let continuation = actionContinuation {
            actionContinuation = nil
            pendingTurn = nil
            continuation.resume(returning: .stand)
        }
    }

    public var isWaitingForBet: Bool { betContinuation != nil }
    public var isWaitingForAction: Bool { actionContinuation != nil }
}

/// A provider that plays a fixed script — for tests and for driving a session
/// at code speed without an interface.
public struct ScriptedBlackjackActionProvider: BlackjackActionProvider {
    private let bet: Int
    private let rounds: Int
    private let decide: @Sendable (BlackjackTurnContext) -> BlackjackAction

    public init(bet: Int, rounds: Int = .max,
                decide: @escaping @Sendable (BlackjackTurnContext) -> BlackjackAction) {
        self.bet = bet
        self.rounds = rounds
        self.decide = decide
    }

    public func provideBet(for context: BlackjackBetContext) async -> Int? {
        min(max(bet, context.minimumBet), min(context.maximumBet, context.chips))
    }

    public func provideAction(for context: BlackjackTurnContext) async -> BlackjackAction {
        decide(context)
    }
}
