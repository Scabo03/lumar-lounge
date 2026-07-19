// BlackjackRound.swift
// =====================================================================
// One round of blackjack: the player (alone) against the house.
//
// Shape follows the other engines — a value type with `mutating apply(_:)`,
// validation in small private helpers, and ALL progression funnelled through
// one `progress()` function — but the substance is different. There is no
// pot, no opponent, and no betting street: the player resolves each of their
// hands in turn, then the dealer plays once against whatever is left.
//
// Determinism: the only source of randomness is the shoe, which carries its
// own seeded generator. Same shoe state + same actions ⇒ same round.

import Foundation

/// A single round of blackjack, from the deal to the settled account.
public struct BlackjackRound: Sendable {

    // MARK: Configuration

    public let rules: BlackjackRules

    /// The wager the round opened with, before any double or split.
    public let openingBet: Int

    // MARK: Observable state

    /// The player's hands, in play order. Starts as one and grows by splitting.
    public private(set) var hands: [BlackjackPlayerHand]

    /// The dealer's cards. The second one is face down until the dealer plays.
    public private(set) var dealerCards: [Card]

    /// Whether the dealer's second card is still face down.
    public private(set) var holeCardHidden: Bool

    /// Which hand the player is acting on, or nil when it is no longer their turn.
    public private(set) var activeHandIndex: Int?

    public private(set) var phase: BlackjackPhase

    /// Chips the player still has available to commit to a double or a split.
    public private(set) var bankroll: Int

    public private(set) var result: BlackjackRoundResult?

    /// The shoe, carried in and out so a session can keep dealing from it.
    public private(set) var shoe: Shoe

    // MARK: Derived

    public var isComplete: Bool { result != nil }

    /// The dealer's face-up card — the single piece of dealer information the
    /// player decides on.
    public var dealerUpCard: Card { dealerCards[0] }

    /// The dealer cards the player may see right now.
    public var visibleDealerCards: [Card] {
        holeCardHidden ? [dealerCards[0]] : dealerCards
    }

    /// The dealer total the player may see right now.
    public var visibleDealerTotal: Int {
        BlackjackValue.total(of: visibleDealerCards)
    }

    /// Everything the player currently has at stake.
    public var totalCommitted: Int { hands.reduce(0) { $0 + $1.bet } }

    /// The hand the player is acting on, if any.
    public var activeHand: BlackjackPlayerHand? {
        guard let index = activeHandIndex, hands.indices.contains(index) else { return nil }
        return hands[index]
    }

    // MARK: - Init

    /// Deals a round.
    ///
    /// - Parameters:
    ///   - bet: the opening wager, already deducted from the player's chips by
    ///     the caller.
    ///   - bankroll: chips the player has left AFTER the opening wager — the
    ///     ceiling on doubling and splitting.
    ///   - shoe: the table's shoe, dealt from and handed back.
    public init(bet: Int, bankroll: Int, rules: BlackjackRules = .standard, shoe: Shoe) {
        precondition(bet > 0, "A round needs a positive wager.")
        precondition(bankroll >= 0, "Bankroll cannot be negative.")

        self.rules = rules
        self.openingBet = bet
        self.bankroll = bankroll
        self.shoe = shoe
        self.phase = .playerTurns
        self.holeCardHidden = true
        self.activeHandIndex = 0
        self.dealerCards = []
        self.hands = []

        // The real dealing order: player, dealer up, player, dealer down.
        var deck = self.shoe
        let p1 = deck.draw()
        let dUp = deck.draw()
        let p2 = deck.draw()
        let dDown = deck.draw()
        self.shoe = deck

        self.hands = [BlackjackPlayerHand(cards: [p1, p2], bet: bet)]
        self.dealerCards = [dUp, dDown]

        openRound()
    }

    /// Resolves the two situations that end a round before the player ever acts.
    private mutating func openRound() {
        let dealerNatural = BlackjackValue.isNatural(dealerCards)

        // The dealer looks under an ace or a ten. Finding a natural there ends
        // the round at once, which is what protects the player's double and
        // split money (D-090).
        if rules.dealerPeeks, dealerShowsPeekableCard, dealerNatural {
            finish(dealerActed: false)
            return
        }

        // A dealt 21 is settled immediately; the dealer does not draw against it.
        if hands[0].isNatural {
            finish(dealerActed: false)
            return
        }
    }

    private var dealerShowsPeekableCard: Bool {
        let up = dealerCards[0].rank
        return up == .ace || BlackjackValue.points(up) == 10
    }

    // MARK: - Legality

    /// What the player may do right now, or nil when it is not their turn.
    public func legalActions() -> BlackjackLegalActions? {
        guard phase == .playerTurns, let index = activeHandIndex,
              hands.indices.contains(index) else { return nil }
        let hand = hands[index]
        guard !hand.isResolved else { return nil }

        // Doubling, splitting and surrendering are all opening moves: they are
        // offered only on an untouched two-card hand.
        let isOpeningDecision = hand.cards.count == 2 && !hand.isDoubled && !hand.isStood
        let canAfford = bankroll >= hand.bet

        let canDouble = isOpeningDecision
            && canAfford
            && !hand.isFromSplitAces
            && (hand.splitDepth == 0 || rules.doubleAfterSplit)

        let splitsUsed = hands.count - 1
        let isAcePair = hand.cards.count == 2 && hand.cards.allSatisfy { $0.rank == .ace }
        let canSplit = isOpeningDecision
            && canAfford
            && BlackjackValue.canSplit(hand.cards)
            && splitsUsed < rules.maxSplits
            && !(isAcePair && hand.splitDepth > 0 && !rules.resplitAces)

        // Surrender is a late surrender on the dealt hand only: once the player
        // has split or drawn, the offer is gone.
        let canSurrender = rules.surrenderAllowed
            && isOpeningDecision
            && hands.count == 1
            && hand.splitDepth == 0

        return BlackjackLegalActions(handIndex: index,
                                     canHit: true,
                                     canStand: true,
                                     canDouble: canDouble,
                                     canSplit: canSplit,
                                     canSurrender: canSurrender,
                                     additionalWager: hand.bet)
    }

    // MARK: - Transitions

    public mutating func apply(_ action: BlackjackAction) throws {
        guard result == nil else { throw BlackjackActionError.roundComplete }
        guard phase == .playerTurns, let index = activeHandIndex else {
            throw BlackjackActionError.notPlayerTurn
        }
        guard let legal = legalActions() else {
            throw BlackjackActionError.cannotHitResolvedHand
        }

        switch action {
        case .hit:
            hands[index].cards.append(shoe.draw())

        case .stand:
            hands[index].isStood = true

        case .double:
            guard legal.canDouble else {
                throw bankroll < hands[index].bet
                    ? BlackjackActionError.insufficientChips
                    : BlackjackActionError.cannotDouble
            }
            bankroll -= hands[index].bet
            hands[index].bet *= 2
            hands[index].isDoubled = true
            hands[index].cards.append(shoe.draw())

        case .split:
            guard legal.canSplit else {
                throw bankroll < hands[index].bet
                    ? BlackjackActionError.insufficientChips
                    : BlackjackActionError.cannotSplit
            }
            applySplit(at: index)

        case .surrender:
            guard legal.canSurrender else { throw BlackjackActionError.cannotSurrender }
            hands[index].isSurrendered = true
        }

        progress()
    }

    private mutating func applySplit(at index: Int) {
        let original = hands[index]
        let wasAces = original.cards.allSatisfy { $0.rank == .ace }
        let depth = original.splitDepth + 1

        bankroll -= original.bet

        var left = BlackjackPlayerHand(cards: [original.cards[0]], bet: original.bet,
                                       splitDepth: depth, isFromSplitAces: wasAces)
        var right = BlackjackPlayerHand(cards: [original.cards[1]], bet: original.bet,
                                        splitDepth: depth, isFromSplitAces: wasAces)

        left.cards.append(shoe.draw())
        right.cards.append(shoe.draw())

        // Split aces receive one card each and are finished — marking them stood
        // keeps the rule in one place instead of leaking into `isResolved`.
        if wasAces && rules.oneCardToSplitAces {
            left.isStood = true
            right.isStood = true
        }

        hands[index] = left
        hands.insert(right, at: index + 1)
    }

    /// The single progression point: advance past resolved hands, and hand over
    /// to the dealer when the player has none left to play.
    private mutating func progress() {
        guard phase == .playerTurns, var index = activeHandIndex else { return }
        while index < hands.count && hands[index].isResolved { index += 1 }
        if index >= hands.count {
            activeHandIndex = nil
            playDealer()
        } else {
            activeHandIndex = index
        }
    }

    private mutating func playDealer() {
        phase = .dealerPlay
        holeCardHidden = false

        // The dealer plays only when a hand is still standing that a draw could
        // actually beat. Against nothing but busts, surrenders and naturals the
        // dealer simply shows the hole card.
        let worthPlaying = hands.contains { !$0.isBust && !$0.isSurrendered && !$0.isNatural }
        guard worthPlaying else {
            finish(dealerActed: false)
            return
        }

        while shouldDealerDraw {
            dealerCards.append(shoe.draw())
        }
        finish(dealerActed: true)
    }

    /// The house rule: the dealer stands on every 17, soft ones included.
    private var shouldDealerDraw: Bool {
        let (total, isSoft) = BlackjackValue.total(dealerCards)
        if total < 17 { return true }
        if total == 17 && isSoft && !rules.dealerStandsOnSoft17 { return true }
        return false
    }

    // MARK: - Settlement

    private mutating func finish(dealerActed: Bool) {
        holeCardHidden = false

        let dealerNatural = BlackjackValue.isNatural(dealerCards)
        let dealerTotal = BlackjackValue.total(of: dealerCards)
        let dealerBusted = dealerTotal > 21

        let settled = hands.map { hand -> BlackjackHandResult in
            let (outcome, returned) = settle(hand,
                                             dealerNatural: dealerNatural,
                                             dealerTotal: dealerTotal,
                                             dealerBusted: dealerBusted)
            return BlackjackHandResult(cards: hand.cards,
                                       total: hand.total,
                                       bet: hand.bet,
                                       outcome: outcome,
                                       returned: returned)
        }

        result = BlackjackRoundResult(hands: settled,
                                      dealerCards: dealerCards,
                                      dealerTotal: dealerTotal,
                                      dealerHasNatural: dealerNatural,
                                      dealerBusted: dealerBusted,
                                      dealerPlayed: dealerActed)
        phase = .settled
        activeHandIndex = nil
    }

    /// The whole payout table, in one place.
    private func settle(_ hand: BlackjackPlayerHand,
                        dealerNatural: Bool,
                        dealerTotal: Int,
                        dealerBusted: Bool) -> (BlackjackOutcome, Int) {
        if hand.isSurrendered {
            return (.surrender, hand.bet / 2)
        }
        if hand.isBust {
            return (.bust, 0)
        }
        if hand.isNatural {
            if dealerNatural { return (.push, hand.bet) }
            let winnings = hand.bet * rules.naturalPayoutNumerator / rules.naturalPayoutDenominator
            return (.natural, hand.bet + winnings)
        }
        if dealerNatural {
            return (.lose, 0)
        }
        if dealerBusted {
            return (.win, hand.bet * 2)
        }
        if hand.total > dealerTotal { return (.win, hand.bet * 2) }
        if hand.total == dealerTotal { return (.push, hand.bet) }
        return (.lose, 0)
    }
}
