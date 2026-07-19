// BlackjackTableState.swift
// =====================================================================
// The pure presentation state of a blackjack table, and the pure reduction
// of events into it. No SwiftUI, no localization, no game logic — so the
// whole thing is unit-testable with `swift test` (D-017).

import Foundation
import GameEngine
import GameWorld

/// One of the player's hands, as the table shows it.
public struct BlackjackHandPresentation: Equatable, Sendable {
    public var cards: [Card]
    public var bet: Int
    public var outcome: BlackjackOutcome?

    public init(cards: [Card], bet: Int, outcome: BlackjackOutcome? = nil) {
        self.cards = cards
        self.bet = bet
        self.outcome = outcome
    }

    public var total: Int { BlackjackValue.total(cards).total }
    public var isSoft: Bool { BlackjackValue.total(cards).isSoft }
    public var isBust: Bool { total > 21 }
}

public struct BlackjackTableState: Equatable, Sendable {
    public var chips: Int
    public var minimumBet: Int
    public var maximumBet: Int

    public var roundNumber: Int?
    public var bet: Int

    public var hands: [BlackjackHandPresentation]
    public var activeHandIndex: Int?

    /// The dealer cards the player may currently see.
    public var dealerCards: [Card]
    /// Whether the dealer's second card is still face down.
    public var holeCardHidden: Bool
    public var dealerHasNatural: Bool
    public var dealerBusted: Bool

    /// What the last settled round earned or cost, for the table's own display.
    public var lastRoundNet: Int?
    public var finished: Bool

    public init(chips: Int = 0, minimumBet: Int = 0, maximumBet: Int = 0,
                roundNumber: Int? = nil, bet: Int = 0,
                hands: [BlackjackHandPresentation] = [], activeHandIndex: Int? = nil,
                dealerCards: [Card] = [], holeCardHidden: Bool = true,
                dealerHasNatural: Bool = false, dealerBusted: Bool = false,
                lastRoundNet: Int? = nil, finished: Bool = false) {
        self.chips = chips
        self.minimumBet = minimumBet
        self.maximumBet = maximumBet
        self.roundNumber = roundNumber
        self.bet = bet
        self.hands = hands
        self.activeHandIndex = activeHandIndex
        self.dealerCards = dealerCards
        self.holeCardHidden = holeCardHidden
        self.dealerHasNatural = dealerHasNatural
        self.dealerBusted = dealerBusted
        self.lastRoundNet = lastRoundNet
        self.finished = finished
    }

    /// The dealer total the player can currently work out — the face-up cards
    /// only, while the hole card is down.
    public var dealerTotal: Int { BlackjackValue.total(of: dealerCards) }

    public var dealerUpCard: Card? { dealerCards.first }

    /// True once the player holds more than one hand, which is the only
    /// situation where hands need to be told apart by number.
    public var hasSplit: Bool { hands.count > 1 }

    public var activeHand: BlackjackHandPresentation? {
        guard let index = activeHandIndex, hands.indices.contains(index) else { return nil }
        return hands[index]
    }

    /// Everything currently at stake.
    public var totalAtStake: Int { hands.reduce(0) { $0 + $1.bet } }
}

/// The wager input, built on the increment pattern CONVENTIONS §4 (D-020) set
/// aside for exactly this: a click COUNT as the source of truth, the value
/// derived and clamped to the legal band, and a pure curve on the side.
///
/// The curve here is linear in table minimums rather than poker's accelerating
/// one, because a blackjack table's chips ARE its minimum: a twenty-chip table
/// is played in twenties. Snapping to whole multiples is also what keeps three
/// to two and half-back-on-surrender exact in whole chips.
public struct BlackjackBetBox: Equatable, Sendable {
    public var clicks: Int
    public let minimum: Int
    public let ceiling: Int

    public init(minimum: Int, maximum: Int, opening: Int? = nil) {
        self.minimum = max(1, minimum)
        // The real ceiling is the largest whole multiple of the minimum that
        // still fits under the table maximum and the player's fiches.
        self.ceiling = max(self.minimum, (max(maximum, self.minimum) / self.minimum) * self.minimum)
        let start = opening ?? self.minimum
        let stepped = (max(start, self.minimum) / self.minimum) * self.minimum
        self.clicks = max(0, (min(stepped, self.ceiling) - self.minimum) / self.minimum)
    }

    public var value: Int {
        min(ceiling, minimum + clicks * minimum)
    }

    public var isAtMax: Bool { value >= ceiling }
    public var isAtMin: Bool { clicks == 0 }

    public mutating func increase() {
        guard !isAtMax else { return }
        clicks += 1
    }

    public mutating func decrease() {
        guard !isAtMin else { return }
        clicks -= 1
    }

    public mutating func toMax() {
        clicks = (ceiling - minimum) / minimum
    }
}

public enum BlackjackTableReducer {

    public static func reduce(_ state: BlackjackTableState,
                              _ payload: BlackjackEventPayload) -> BlackjackTableState {
        var next = state

        switch payload {
        case let .sessionBegan(chips, minimumBet, maximumBet):
            next.chips = chips
            next.minimumBet = minimumBet
            next.maximumBet = maximumBet

        case .shoeShuffled:
            break   // audible, not visible

        case let .roundBegan(roundNumber, bet, chips):
            next.roundNumber = roundNumber
            next.bet = bet
            next.chips = chips
            next.hands = []
            next.activeHandIndex = nil
            next.dealerCards = []
            next.holeCardHidden = true
            next.dealerHasNatural = false
            next.dealerBusted = false
            next.lastRoundNet = nil

        case let .dealt(playerCards, _, _, dealerUpCard, _):
            next.hands = [BlackjackHandPresentation(cards: playerCards, bet: next.bet)]
            next.activeHandIndex = 0
            next.dealerCards = [dealerUpCard]
            next.holeCardHidden = true

        case let .handTurnBegan(handIndex, _, _, _, _):
            next.activeHandIndex = handIndex

        case let .playerActed(handIndex, action, chips):
            apply(&next, handIndex, action)
            next.chips = chips

        case let .dealerPlayed(cards, _, _, didBust, hasNatural, _):
            next.dealerCards = cards
            next.holeCardHidden = false
            next.dealerBusted = didBust
            next.dealerHasNatural = hasNatural
            next.activeHandIndex = nil

        case let .handSettled(handIndex, _, outcome, _, bet, _):
            guard next.hands.indices.contains(handIndex) else { break }
            next.hands[handIndex].outcome = outcome
            next.hands[handIndex].bet = bet

        case let .roundEnded(_, net, chips, _):
            next.chips = chips
            next.lastRoundNet = net
            next.activeHandIndex = nil

        case .sessionEnded:
            next.finished = true
        }

        return next
    }

    private static func apply(_ state: inout BlackjackTableState,
                              _ index: Int,
                              _ action: BlackjackActedAction) {
        switch action {
        case let .hit(card, _, _, _):
            guard state.hands.indices.contains(index) else { return }
            state.hands[index].cards.append(card)

        case .stood:
            break

        case let .doubled(card, _, wager, _):
            guard state.hands.indices.contains(index) else { return }
            state.hands[index].cards.append(card)
            state.hands[index].bet = wager

        case let .split(hands, wager):
            // The split event carries the whole picture, so the table is rebuilt
            // from it rather than guessed at.
            state.hands = hands.map { BlackjackHandPresentation(cards: $0, bet: wager) }

        case .surrendered:
            break
        }
    }
}
