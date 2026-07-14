// MachiavelliWorkspace.swift
// =====================================================================
// The human's WORKING turn state (D-072): the in-progress arrangement of the table and
// hand while the player composes their turn, BEFORE it is submitted to the driver. It
// is the substrate both input modes mutate — the composition box (accessible) and drag
// (sighted) — and it is deliberately allowed to be TRANSIENTLY INVALID: confirming a
// combination in the box may steal a card from another combination and leave it broken,
// to be fixed by a further composition. Only the TERMINAL (Pass) is gated on the whole
// table being valid.
//
// CRUCIAL INVARIANT (D-072): this struct holds NO validity logic. Whether a set of cards
// is a legal combination, and whether the whole table is valid, is answered ONLY by the
// engine's pure predicate (`MachiavelliRules.classify` / `isValidTable`) — the single
// source of truth both input modes query. This struct is pure BOOKKEEPING of where each
// card instance currently sits; it never judges legality.
//
// Cards are tracked by stable INSTANCE INDEX (not by value) so the two decks' duplicate
// cards are handled correctly, and so a card placed this turn can be picked up and
// recomposed any number of times. Indices [0, handStart) are HAND-origin (may return to
// hand); [handStart, n) are TABLE-origin (stay on the table — a table card is never
// pocketed, which the engine also enforces as conservation).

import Foundation
import GameEngine

struct MachiavelliWorkspace: Equatable {
    /// index → the concrete card (immutable for the turn).
    private let cardAt: [Card]
    /// The number of cards in the hand at turn start; indices below it are hand-origin.
    let handStart: Int
    /// The working hand as instance indices.
    private(set) var handIndices: [Int]
    /// The working table as groups of instance indices (a group may be transiently invalid).
    private(set) var tableGroups: [[Int]]

    /// Builds the workspace from the committed hand + table at the turn's start.
    init(hand: [Card], table: [[Card]]) {
        var cards: [Card] = []
        var handIdx: [Int] = []
        for card in hand { handIdx.append(cards.count); cards.append(card) }
        var groups: [[Int]] = []
        for meld in table {
            var g: [Int] = []
            for card in meld { g.append(cards.count); cards.append(card) }
            groups.append(g)
        }
        self.cardAt = cards
        self.handStart = hand.count
        self.handIndices = handIdx
        self.tableGroups = groups
    }

    // MARK: - Lookups

    func card(_ index: Int) -> Card { cardAt[index] }
    func isHandOrigin(_ index: Int) -> Bool { index < handStart }

    /// The working hand, in stable display order (D-072).
    var handCards: [(index: Int, card: Card)] {
        handIndices.map { ($0, cardAt[$0]) }.sorted { cardDisplayOrder($0.card, $1.card) }
    }
    /// The working table, group by group, each in canonical order when it forms a legal
    /// combination (else in a stable order). The cards only.
    var meldCards: [[Card]] {
        tableGroups.map { group in
            let cards = group.map { cardAt[$0] }
            return Meld(cards)?.cards ?? cards.sorted(by: cardDisplayOrder)
        }
    }
    /// The table groups as (index, card) pairs, canonically ordered — for the box chain
    /// and the table's per-card navigation.
    var tableEntries: [[(index: Int, card: Card)]] {
        tableGroups.map { group in
            let pairs = group.map { (index: $0, card: cardAt[$0]) }
            if let meld = Meld(pairs.map { $0.card }) {
                // Re-order the pairs to match the meld's canonical card order.
                var remaining = pairs
                return meld.cards.compactMap { card -> (index: Int, card: Card)? in
                    guard let pos = remaining.firstIndex(where: { $0.card == card }) else { return nil }
                    return remaining.remove(at: pos)
                }
            }
            return pairs.sorted { cardDisplayOrder($0.card, $1.card) }
        }
    }

    // MARK: - Derived state (queried from the engine predicate — the single truth)

    /// Net hand cards placed this turn (hand shrank).
    var placedCount: Int { handStart - handIndices.count }
    /// Whether the whole table is valid — asked of the ENGINE, never judged here.
    var tableIsValid: Bool { MachiavelliRules.isValidTable(meldCards) }
    /// May end the turn by passing: placed ≥1 AND the table is valid.
    var canPass: Bool { placedCount > 0 && tableIsValid }
    /// Must end the turn by drawing: placed nothing on net.
    var mustDraw: Bool { placedCount == 0 }
    /// Would passing now win the hand (hand emptied)?
    var handIsEmpty: Bool { handIndices.isEmpty }
    /// The arrangement to submit to the driver.
    var finalArrangement: [[Card]] { meldCards }

    // MARK: - Mutations (pure bookkeeping)

    /// Whether a selection of instance indices forms a LEGAL combination — asked of the
    /// engine (`classify`). This is the gate the box's Confirm uses.
    func selectionIsLegalCombination(_ indices: [Int]) -> Bool {
        MachiavelliRules.classify(indices.map { cardAt[$0] }) != nil
    }

    /// Confirms a composed combination: forms the selected indices into a new table
    /// group, removing them from wherever they currently sit (hand or other groups).
    /// Caller has verified `selectionIsLegalCombination` (Confirm was enabled).
    mutating func placeCombination(_ indices: [Int]) {
        detach(indices)
        tableGroups.append(indices)
        dropEmptyGroups()
    }

    /// Drag support: moves an instance index into an existing table group (append) or,
    /// when `groupIndex` is nil, into a NEW group. Table-origin cards may move among
    /// groups; hand-origin cards may move from hand to a group.
    mutating func moveToGroup(_ index: Int, groupIndex: Int?) {
        detach([index])
        if let g = groupIndex, tableGroups.indices.contains(g) {
            tableGroups[g].append(index)
        } else {
            tableGroups.append([index])
        }
        dropEmptyGroups()
    }

    /// Retracts a HAND-ORIGIN card that was placed this turn back to the hand (an undo
    /// of a placement). A table-origin card is never pocketed (no-op).
    mutating func retractToHand(_ index: Int) {
        guard isHandOrigin(index), !handIndices.contains(index) else { return }
        detach([index])
        handIndices.append(index)
        dropEmptyGroups()
    }

    // MARK: - Helpers

    private mutating func detach(_ indices: [Int]) {
        let set = Set(indices)
        handIndices.removeAll { set.contains($0) }
        for i in tableGroups.indices { tableGroups[i].removeAll { set.contains($0) } }
    }
    private mutating func dropEmptyGroups() { tableGroups.removeAll { $0.isEmpty } }
}
