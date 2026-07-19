// BlackjackSessionDriver.swift
// =====================================================================
// Runs a blackjack session: round after round against the house.
//
// A pure client of the engine — it never reaches inside `BlackjackRound`,
// only calls its public surface. It owns the things a SESSION owns and a
// round does not: the player's fiches, the shoe carried from round to round,
// the wager limits, and the narration.
//
// The producer runs at code speed and knows nothing about the human rhythm:
// pacing lives entirely in the consumer (D-018).

import Foundation
import GameEngine

public struct BlackjackRoundOutcome: Sendable {
    public let roundNumber: Int
    public let bet: Int
    public let result: BlackjackRoundResult
    public let chipsAfter: Int
    public var net: Int { result.net }
}

public enum BlackjackSessionError: Error, Equatable, Sendable {
    case sessionEnded
    case roundInProgress
    case notEnoughChips
}

public final class BlackjackSessionDriver {

    // MARK: Configuration

    public let minimumBet: Int
    public let maximumBet: Int
    public let houseRules: BlackjackRules

    private let provider: BlackjackActionProvider
    private let hub = BlackjackEventHub()

    // MARK: State

    public private(set) var chips: Int
    public private(set) var roundNumber: Int = 0
    public private(set) var isRoundInProgress = false
    public private(set) var hasEnded = false

    private var shoe: Shoe
    private var sessionAnnounced = false
    private var lastBet: Int?

    // MARK: Init

    /// - Parameter seed: fixed in tests for reproducibility; `nil` in
    ///   production, where the shoe is seeded from the system generator.
    ///
    ///   Note the shape is slightly different from the poker drivers, and
    ///   deliberately so (D-090): poker reseeds per hand because each hand is
    ///   dealt from a fresh deck, whereas a blackjack shoe genuinely PERSISTS
    ///   across rounds. One random seed per session therefore gives exactly
    ///   what D-047 asks for — every session and every round different — while
    ///   modelling the shoe honestly.
    public init(chips: Int,
                rules: BlackjackTableRules,
                provider: BlackjackActionProvider,
                seed: UInt64? = nil) {
        self.chips = chips
        self.minimumBet = rules.minimumBet
        self.maximumBet = rules.maximumBet
        self.houseRules = rules.rules
        self.provider = provider
        self.shoe = Shoe(deckCount: rules.rules.deckCount,
                         penetration: rules.rules.penetration,
                         seed: seed ?? UInt64.random(in: .min ... .max))
    }

    // MARK: Queries

    public var canDealNextRound: Bool {
        !hasEnded && !isRoundInProgress && chips >= minimumBet
    }

    /// The largest wager the player could actually place right now.
    public var currentMaximumBet: Int { min(maximumBet, chips) }

    public func events(as viewer: EventViewer = .spectator) async -> AsyncStream<BlackjackSessionEvent> {
        await hub.subscribe(as: viewer)
    }

    // MARK: Playing

    /// Plays one round.
    ///
    /// - Returns: the settled round, or `nil` when the player declined to
    ///   wager (which is how leaving the table arrives here).
    @discardableResult
    public func playRound() async throws -> BlackjackRoundOutcome? {
        guard !hasEnded else { throw BlackjackSessionError.sessionEnded }
        guard !isRoundInProgress else { throw BlackjackSessionError.roundInProgress }
        guard chips >= minimumBet else { throw BlackjackSessionError.notEnoughChips }

        isRoundInProgress = true
        defer { isRoundInProgress = false }

        await announceSessionIfNeeded()

        // The cut card is checked BETWEEN rounds, never inside one.
        if shoe.needsShuffle {
            shoe.reshuffle()
            await hub.emit(.shoeShuffled(roundNumber: roundNumber + 1))
        }

        let betContext = BlackjackBetContext(chips: chips,
                                             minimumBet: minimumBet,
                                             maximumBet: currentMaximumBet,
                                             lastBet: lastBet)
        guard let requested = await provider.provideBet(for: betContext) else { return nil }
        let bet = clampBet(requested)
        lastBet = bet

        chips -= bet
        await hub.emit(.roundBegan(roundNumber: roundNumber + 1, bet: bet, chips: chips))

        var round = BlackjackRound(bet: bet, bankroll: chips, rules: houseRules, shoe: shoe)

        let opening = round.hands[0]
        await hub.emit(.dealt(playerCards: opening.cards,
                              total: opening.total,
                              isSoft: opening.isSoft,
                              dealerUpCard: round.dealerUpCard,
                              isNatural: opening.isNatural))

        var announcedHand: Int?
        while !round.isComplete, let legal = round.legalActions() {
            let index = legal.handIndex
            let hand = round.hands[index]

            // A split creates hands the player did not ask for; announcing the
            // handover is what keeps them oriented across several hands at once.
            if announcedHand != index {
                await hub.emit(.handTurnBegan(handIndex: index,
                                              cards: hand.cards,
                                              total: hand.total,
                                              isSoft: hand.isSoft,
                                              handCount: round.hands.count))
                announcedHand = index
            }

            let requestedAction = await provider.provideAction(for: turnContext(round, legal: legal))
            let action = legalize(requestedAction, legal)

            let cardsBefore = round.hands[index].cards.count
            let handsBefore = round.hands.count
            try round.apply(action)
            chips = round.bankroll

            await hub.emit(.playerActed(handIndex: index,
                                        action: classify(action,
                                                         in: round,
                                                         index: index,
                                                         cardsBefore: cardsBefore,
                                                         handsBefore: handsBefore),
                                        chips: chips))
        }

        guard let result = round.result else { return nil }
        shoe = round.shoe

        let (dealerTotal, dealerSoft) = BlackjackValue.total(result.dealerCards)
        await hub.emit(.dealerPlayed(cards: result.dealerCards,
                                     total: dealerTotal,
                                     isSoft: dealerSoft,
                                     didBust: result.dealerBusted,
                                     hasNatural: result.dealerHasNatural,
                                     drew: result.dealerPlayed))

        for (index, hand) in result.hands.enumerated() {
            await hub.emit(.handSettled(handIndex: index,
                                        handCount: result.hands.count,
                                        outcome: hand.outcome,
                                        total: hand.total,
                                        bet: hand.bet,
                                        net: hand.net))
        }

        chips += result.totalReturned
        roundNumber += 1
        await hub.emit(.roundEnded(roundNumber: roundNumber,
                                   net: result.net,
                                   chips: chips,
                                   handCount: result.hands.count))

        return BlackjackRoundOutcome(roundNumber: roundNumber,
                                     bet: bet,
                                     result: result,
                                     chipsAfter: chips)
    }

    @discardableResult
    public func run(maxRounds: Int = .max,
                    continuing shouldContinue: (BlackjackRoundOutcome) -> Bool = { _ in true })
    async throws -> [BlackjackRoundOutcome] {
        var outcomes: [BlackjackRoundOutcome] = []
        while outcomes.count < maxRounds, canDealNextRound {
            guard let outcome = try await playRound() else { break }
            outcomes.append(outcome)
            if !shouldContinue(outcome) { break }
        }
        return outcomes
    }

    public func endSession(reason: BlackjackSessionEndReason = .stopped) async {
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
        await hub.emit(.sessionBegan(chips: chips,
                                     minimumBet: minimumBet,
                                     maximumBet: maximumBet))
    }

    /// Wagers are clamped into the legal band and rounded down to a whole
    /// multiple of the minimum, which is what keeps every payout exact.
    private func clampBet(_ requested: Int) -> Int {
        let ceiling = min(maximumBet, chips)
        let clamped = min(max(requested, minimumBet), ceiling)
        let stepped = (clamped / minimumBet) * minimumBet
        return max(minimumBet, min(stepped, ceiling))
    }

    private func turnContext(_ round: BlackjackRound,
                             legal: BlackjackLegalActions) -> BlackjackTurnContext {
        let hand = round.hands[legal.handIndex]
        return BlackjackTurnContext(handIndex: legal.handIndex,
                                    handCount: round.hands.count,
                                    cards: hand.cards,
                                    total: hand.total,
                                    isSoft: hand.isSoft,
                                    bet: hand.bet,
                                    dealerUpCard: round.dealerUpCard,
                                    chips: round.bankroll,
                                    legal: legal)
    }

    /// The driver never trusts a provider: an illegal request degrades to a
    /// legal one rather than throwing, so the session stays total even with a
    /// misbehaving or abandoned provider (D-013).
    private func legalize(_ action: BlackjackAction,
                          _ legal: BlackjackLegalActions) -> BlackjackAction {
        legal.allowed.contains(action) ? action : .stand
    }

    /// Turns an applied action plus the before/after difference into a
    /// self-contained event, so no listener has to reconstruct amounts.
    private func classify(_ action: BlackjackAction,
                          in round: BlackjackRound,
                          index: Int,
                          cardsBefore: Int,
                          handsBefore: Int) -> BlackjackActedAction {
        let hand = round.hands.indices.contains(index) ? round.hands[index] : nil
        switch action {
        case .hit:
            let drawn = hand?.cards.last ?? round.dealerUpCard
            return .hit(card: drawn,
                        total: hand?.total ?? 0,
                        isSoft: hand?.isSoft ?? false,
                        didBust: hand?.isBust ?? false)
        case .stand:
            return .stood(total: hand?.total ?? 0)
        case .double:
            let drawn = hand?.cards.last ?? round.dealerUpCard
            return .doubled(card: drawn,
                            total: hand?.total ?? 0,
                            wager: hand?.bet ?? 0,
                            didBust: hand?.isBust ?? false)
        case .split:
            _ = cardsBefore
            _ = handsBefore
            return .split(hands: round.hands.map(\.cards), wager: hand?.bet ?? 0)
        case .surrender:
            return .surrendered(refund: (hand?.bet ?? 0) / 2)
        }
    }
}
