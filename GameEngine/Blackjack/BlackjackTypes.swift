// BlackjackTypes.swift
// =====================================================================
// The value types of the blackjack engine: house rules, the player's
// actions, one (possibly split) hand, legality, and the settled result.
//
// Blackjack is the first game in the project that is NOT a contest between
// players: the player faces the house alone, there is no pot, no side pot
// and no showdown. So this engine shares nothing with the poker engines but
// the foundational card types — in particular it does NOT use `PotMath`,
// whose entire subject (splitting a contested pot) does not exist here.

import Foundation

// MARK: - House rules

/// The house rules of a blackjack table.
///
/// Every rule the house could plausibly vary is a field rather than a
/// constant, so a table's contract is stated in one readable place and each
/// rule is independently testable. `.standard` carries the rules of the
/// project (D-090); the two tables differ only in stakes, never in rules.
public struct BlackjackRules: Equatable, Sendable {

    /// Number of 52-card decks in the shoe.
    public let deckCount: Int

    /// Fraction of the shoe dealt before reshuffling between rounds.
    public let penetration: Double

    /// Whether the dealer stands on a SOFT 17 as well as a hard one.
    /// True here: the dealer stands on all 17s.
    public let dealerStandsOnSoft17: Bool

    /// Payout for a natural, as a fraction of the wager (3/2).
    public let naturalPayoutNumerator: Int
    public let naturalPayoutDenominator: Int

    /// How many times a hand may be split (3 == up to four hands).
    public let maxSplits: Int

    /// Whether doubling is allowed on a hand produced by a split.
    public let doubleAfterSplit: Bool

    /// Whether the player may surrender the opening two cards for half the wager.
    public let surrenderAllowed: Bool

    /// Whether split aces receive exactly one card each and are then done.
    public let oneCardToSplitAces: Bool

    /// Whether a pair of aces produced by a split may be split again.
    public let resplitAces: Bool

    /// Whether the dealer looks at the hole card for a natural when showing an
    /// ace or a ten, resolving the round immediately if there is one.
    public let dealerPeeks: Bool

    public init(deckCount: Int = 6,
                penetration: Double = 0.75,
                dealerStandsOnSoft17: Bool = true,
                naturalPayoutNumerator: Int = 3,
                naturalPayoutDenominator: Int = 2,
                maxSplits: Int = 3,
                doubleAfterSplit: Bool = true,
                surrenderAllowed: Bool = true,
                oneCardToSplitAces: Bool = true,
                resplitAces: Bool = false,
                dealerPeeks: Bool = true) {
        self.deckCount = deckCount
        self.penetration = penetration
        self.dealerStandsOnSoft17 = dealerStandsOnSoft17
        self.naturalPayoutNumerator = naturalPayoutNumerator
        self.naturalPayoutDenominator = naturalPayoutDenominator
        self.maxSplits = maxSplits
        self.doubleAfterSplit = doubleAfterSplit
        self.surrenderAllowed = surrenderAllowed
        self.oneCardToSplitAces = oneCardToSplitAces
        self.resplitAces = resplitAces
        self.dealerPeeks = dealerPeeks
    }

    /// The rules of the house, identical at every Lumar Lounge blackjack table.
    public static let standard = BlackjackRules()
}

// MARK: - Actions

/// What the player may do with the hand in front of them.
///
/// There is deliberately no `insurance` case: insurance is a losing bet and
/// the project does not offer the player a losing move (D-090).
public enum BlackjackAction: Equatable, Hashable, Sendable {
    case hit
    case stand
    case double
    case split
    case surrender
}

public enum BlackjackActionError: Error, Equatable, Sendable {
    case roundComplete
    case notPlayerTurn
    case cannotHitResolvedHand
    case cannotDouble
    case cannotSplit
    case cannotSurrender
    case insufficientChips
}

// MARK: - Phase

/// The coarse phase of a round. Blackjack has no betting streets: the player
/// resolves each of their hands in turn, then the dealer plays once.
public enum BlackjackPhase: Equatable, Sendable {
    case playerTurns
    case dealerPlay
    case settled
}

// MARK: - One hand

/// One of the player's hands. A round starts with one and grows by splitting.
public struct BlackjackPlayerHand: Equatable, Sendable {
    public internal(set) var cards: [Card]

    /// The wager on THIS hand. A split copies the original wager onto the new
    /// hand; a double adds the same amount again.
    public internal(set) var bet: Int

    public internal(set) var isDoubled: Bool
    public internal(set) var isSurrendered: Bool
    public internal(set) var isStood: Bool

    /// How many splits produced this hand. Zero means it was dealt, which is
    /// what makes a natural a natural (D-090).
    public internal(set) var splitDepth: Int

    /// Whether this hand came from splitting a pair of aces, which under the
    /// house rule receives exactly one card and is then finished.
    public internal(set) var isFromSplitAces: Bool

    init(cards: [Card], bet: Int, splitDepth: Int = 0, isFromSplitAces: Bool = false) {
        self.cards = cards
        self.bet = bet
        self.isDoubled = false
        self.isSurrendered = false
        self.isStood = false
        self.splitDepth = splitDepth
        self.isFromSplitAces = isFromSplitAces
    }

    public var total: Int { BlackjackValue.total(cards).total }
    public var isSoft: Bool { BlackjackValue.total(cards).isSoft }
    public var isBust: Bool { total > 21 }

    /// A natural pays 3:2 — but only when the hand was DEALT. Twenty-one
    /// assembled after a split is an ordinary twenty-one (D-090).
    public var isNatural: Bool {
        splitDepth == 0 && BlackjackValue.isNatural(cards)
    }

    /// Whether this hand can still receive an action.
    public var isResolved: Bool {
        isBust || isStood || isSurrendered || isDoubled || total == 21
    }
}

// MARK: - Legality

/// What the player may legally do with the hand currently in front of them.
///
/// Every flag is already resolved against the rules, the cards AND the
/// player's remaining chips, so a caller (bot, UI, or driver) can offer
/// exactly these and nothing else.
public struct BlackjackLegalActions: Equatable, Sendable {
    public let handIndex: Int
    public let canHit: Bool
    public let canStand: Bool
    public let canDouble: Bool
    public let canSplit: Bool
    public let canSurrender: Bool

    /// The extra chips a double or a split would commit.
    public let additionalWager: Int

    public var allowed: Set<BlackjackAction> {
        var set: Set<BlackjackAction> = []
        if canHit { set.insert(.hit) }
        if canStand { set.insert(.stand) }
        if canDouble { set.insert(.double) }
        if canSplit { set.insert(.split) }
        if canSurrender { set.insert(.surrender) }
        return set
    }
}

// MARK: - Result

/// How one hand finished against the dealer.
public enum BlackjackOutcome: Equatable, Sendable {
    /// A dealt 21 that beat the dealer — pays 3:2.
    case natural
    /// An ordinary win — pays 1:1.
    case win
    /// Same total as the dealer — the wager comes back.
    case push
    /// The dealer's hand was better.
    case lose
    /// Over 21 — lost regardless of what the dealer does.
    case bust
    /// Abandoned after the deal for half the wager.
    case surrender
}

/// The settled account of one of the player's hands.
public struct BlackjackHandResult: Equatable, Sendable {
    public let cards: [Card]
    public let total: Int
    public let bet: Int
    public let outcome: BlackjackOutcome

    /// Chips handed back to the player for this hand, wager included.
    /// A 1:1 win returns twice the wager; a push returns it; a loss returns none.
    public let returned: Int

    /// What the hand actually earned or cost.
    public var net: Int { returned - bet }
}

/// The settled account of a whole round.
public struct BlackjackRoundResult: Equatable, Sendable {
    public let hands: [BlackjackHandResult]
    public let dealerCards: [Card]
    public let dealerTotal: Int
    public let dealerHasNatural: Bool
    public let dealerBusted: Bool

    /// Whether the dealer drew at all. The dealer does not play out a hand
    /// nobody is left to beat.
    public let dealerPlayed: Bool

    public var totalWagered: Int { hands.reduce(0) { $0 + $1.bet } }
    public var totalReturned: Int { hands.reduce(0) { $0 + $1.returned } }
    public var net: Int { totalReturned - totalWagered }
}
