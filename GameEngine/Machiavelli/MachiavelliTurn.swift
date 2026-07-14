// MachiavelliTurn.swift
// =====================================================================
// THE TURN MODEL — the central architectural decision of Machiavelli (D-070).
//
// A turn is NOT a single move. It is a SEQUENCE of valid transformations of the
// table, closed by an explicit TERMINAL action. During the turn the player applies
// as many transformations as they like, in any order; the turn ends only when they
// pass (having placed at least one card) or draw (having placed none). Intermediate
// transformations never end the turn.
//
// TWO PROPERTIES this model must guarantee, both for accessibility (D-070):
//
//  1. HYPOTHETICAL WORK. A proposal can be EVALUATED without being APPLIED. The
//     future UI lets a player select cards (from hand and table) into a pool that has
//     no effect until confirmed; deselecting is always free; only confirmation mutates
//     the table. `evaluate(_:)` answers "would this be legal, and what would it place?"
//     with zero mutation; `apply(_:)` commits. The box is a safe place to be wrong —
//     which matters far more to a blind player exploring by swipe than to a sighted one.
//
//  2. THE SAME CARD MOVES MANY TIMES. Every proposal is validated against the
//     IMMUTABLE turn-START snapshot (the table as it was when the turn began + the
//     player's initial hand), NOT against the latest working state. So a card placed
//     early can be picked back up and recomposed differently any number of times within
//     the turn; only the FINAL state, at the terminal, must be valid. This is
//     accessibility disguised as a rule: a slow explorer is never punished for the
//     length of their exploration, only for the quality of their final arrangement.
//
// CONSERVATION (the rule the predicate enforces): a proposed table must still contain
// every card that was on the table at turn start (you may shuffle table cards among
// combinations, but never take one into your hand), and any EXTRA cards must come from
// your initial hand. Whatever hand cards you don't place stay in your hand.
//
// Foundation only. This is pure: it holds hand + table, never a deck/stock (drawing
// is the driver's job) and never a clock.

import Foundation

/// The outcome of EVALUATING a proposed whole-table arrangement, without applying it.
public struct MachiavelliProposal: Equatable, Sendable {
    /// Whether the arrangement is legal (valid combinations + conservation).
    public let isLegal: Bool
    /// If illegal, why. `nil` when legal.
    public let rejection: MachiavelliRejection?
    /// The validated melds, when legal (empty when illegal).
    public let melds: [Meld]
    /// The hand cards this arrangement would place onto the table (net vs turn start).
    public let placedFromHand: [Card]
    /// The hand the player would be left with if this arrangement were applied.
    public let resultingHand: [Card]
}

/// A single player's working state during one turn: their hand and the table, plus
/// the immutable turn-start snapshot every proposal is validated against.
public struct MachiavelliTurnContext: Equatable, Sendable {
    public let playerID: Int

    /// The current working hand (reflects the last applied proposal).
    public private(set) var hand: [Card]
    /// The current working table (reflects the last applied proposal). Always valid.
    public private(set) var table: [Meld]

    /// Immutable snapshot: the cards on the table when the turn began. These must
    /// remain on the table for the whole turn (rearrangeable, never pocketable).
    private let lockedTableCards: CardBag
    /// Immutable snapshot: the hand the player held when the turn began.
    private let initialHand: CardBag
    /// The size of the hand at turn start — the terminal rules key off net placement.
    public let initialHandCount: Int

    public init(playerID: Int, hand: [Card], table: [Meld]) {
        self.playerID = playerID
        self.hand = hand
        self.table = table
        self.lockedTableCards = CardBag(table.flatMap { $0.cards })
        self.initialHand = CardBag(hand)
        self.initialHandCount = hand.count
    }

    // MARK: - Hypothetical evaluation (no mutation)

    /// Evaluate a proposed WHOLE-TABLE arrangement (a list of combinations) against
    /// the turn-start snapshot, WITHOUT applying it. This is the pure heart of the
    /// hypothetical model: the UI calls it as the player builds, to know whether the
    /// confirm/end-turn button should unlock and what the move would place.
    public func evaluate(_ arrangement: [[Card]]) -> MachiavelliProposal {
        // 1. Every proposed combination must be legal.
        var melds: [Meld] = []
        melds.reserveCapacity(arrangement.count)
        for group in arrangement {
            if group.isEmpty {
                return .illegal(.emptyCombination)
            }
            guard let meld = Meld(group) else {
                return .illegal(.invalidCombination(group))
            }
            melds.append(meld)
        }

        // 2. Conservation. The proposed cards must contain every locked table card…
        let proposed = CardBag(arrangement.flatMap { $0 })
        guard let extras = proposed.subtracting(lockedTableCards) else {
            return .illegal(.removedTableCard)      // a turn-start table card is missing
        }
        // …and the extra cards (beyond the locked table) must come from the initial hand.
        guard initialHand.contains(extras) else {
            return .illegal(.usedUnavailableCard)
        }

        let resultingHand = initialHand.subtracting(extras)!.cards
        return MachiavelliProposal(isLegal: true, rejection: nil, melds: melds,
                                   placedFromHand: extras.cards, resultingHand: resultingHand)
    }

    // MARK: - Applying (mutation, on confirm only)

    /// Apply a proposed arrangement if it is legal; otherwise throw. Only this mutates.
    public mutating func apply(_ arrangement: [[Card]]) throws {
        let proposal = evaluate(arrangement)
        guard proposal.isLegal else {
            throw MachiavelliError.invalidArrangement(proposal.rejection!)
        }
        table = proposal.melds
        hand = proposal.resultingHand
    }

    // MARK: - Terminal legality

    /// Whether the player may END THE TURN BY PASSING: legal exactly when they have
    /// netted at least one card onto the table this turn (their working hand shrank).
    public var canPass: Bool { hand.count < initialHandCount }

    /// Whether the player must (or may only) END THE TURN BY DRAWING: when they have
    /// placed no card on net this turn. Drawing takes one card from the stock (the
    /// driver performs the physical draw).
    public var mustDraw: Bool { hand.count == initialHandCount }

    /// Whether the working hand is empty — i.e. passing now WINS the game.
    public var handIsEmpty: Bool { hand.isEmpty }
}

private extension MachiavelliProposal {
    static func illegal(_ rejection: MachiavelliRejection) -> MachiavelliProposal {
        MachiavelliProposal(isLegal: false, rejection: rejection, melds: [],
                            placedFromHand: [], resultingHand: [])
    }
}
