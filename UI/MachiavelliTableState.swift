// MachiavelliTableState.swift
// =====================================================================
// The pure presentation state of the Machiavelli table, and the pure reducer that
// folds a `MachiavelliEventPayload` into the next state (D-072). No SwiftUI, no
// localization, no game logic — just what the table currently looks like. As
// everywhere in the UI layer (D-017), the table listens and shows; it never decides.
//
// Machiavelli is not poker: no pot, no bets, no chips at the table. A seat shows only
// a name, how many cards it HOLDS (public), whether it is on turn or THINKING, and its
// running match score. The centre is the shared TABLE of laid combinations; the bottom
// is the human's hand. Both are ORDERED so a large state is searchable without a glance.

import Foundation
import GameWorld
import GameEngine

/// How one seat currently appears at the Machiavelli table.
public struct MachiavelliSeatPresentation: Equatable, Sendable {
    public let id: Int
    public let position: Int
    public var handCount: Int
    /// Running cumulative match score (D-071).
    public var score: Int
    public var isThinking: Bool
    public var wentOut: Bool

    public init(id: Int, position: Int, handCount: Int = 0, score: Int = 0,
                isThinking: Bool = false, wentOut: Bool = false) {
        self.id = id
        self.position = position
        self.handCount = handCount
        self.score = score
        self.isThinking = isThinking
        self.wentOut = wentOut
    }
}

public enum MachiavelliTablePhase: Equatable, Sendable { case idle, playing, finished }

/// Everything the Machiavelli table view needs to draw itself (the COMMITTED table —
/// during the human's own turn the view renders the live workspace instead).
public struct MachiavelliTableState: Equatable, Sendable {
    public var seats: [MachiavelliSeatPresentation]
    /// The shared table: each laid combination as its (canonically ordered) cards.
    public var melds: [[Card]]
    public var heroSeatID: Int?
    /// The human's own hand (ordered), nil until dealt.
    public var heroHand: [Card]?
    public var activeSeatID: Int?
    public var stockCount: Int
    public var handNumber: Int?
    public var phase: MachiavelliTablePhase
    /// The per-player points awarded by the hand that just ended (for a transient
    /// scoreboard), nil between such moments.
    public var lastHandScores: [Int: Int]?

    public init(seats: [MachiavelliSeatPresentation] = [], melds: [[Card]] = [],
                heroSeatID: Int? = nil, heroHand: [Card]? = nil, activeSeatID: Int? = nil,
                stockCount: Int = 0, handNumber: Int? = nil, phase: MachiavelliTablePhase = .idle,
                lastHandScores: [Int: Int]? = nil) {
        self.seats = seats
        self.melds = melds
        self.heroSeatID = heroSeatID
        self.heroHand = heroHand
        self.activeSeatID = activeSeatID
        self.stockCount = stockCount
        self.handNumber = handNumber
        self.phase = phase
        self.lastHandScores = lastHandScores
    }

    public static let empty = MachiavelliTableState()

    public func seat(_ id: Int) -> MachiavelliSeatPresentation? { seats.first { $0.id == id } }

    public var opponents: [MachiavelliSeatPresentation] {
        seats.filter { $0.id != heroSeatID }.sorted { $0.position < $1.position }
    }
    /// The seat currently deliberating (a bot), if any — the audible/visible "thinking".
    public var thinkingSeatID: Int? { seats.first { $0.isThinking }?.id }
}

public enum MachiavelliTableReducer {

    public static func reduce(_ state: MachiavelliTableState, _ payload: MachiavelliEventPayload) -> MachiavelliTableState {
        var next = state
        switch payload {

        case let .sessionBegan(seats, _):
            next.seats = seats.sorted { $0.position < $1.position }
                .map { MachiavelliSeatPresentation(id: $0.seatID, position: $0.position, handCount: $0.handCount) }
            next.phase = .idle

        case let .handBegan(handNumber, seats, firstToAct, stockCount):
            next.handNumber = handNumber
            next.melds = []
            next.heroHand = nil
            next.stockCount = stockCount
            next.activeSeatID = firstToAct
            next.phase = .playing
            next.lastHandScores = nil
            for snapshot in seats {
                mutate(&next, snapshot.seatID) {
                    $0.handCount = snapshot.handCount
                    $0.wentOut = false
                    $0.isThinking = false
                }
            }

        case let .handDealt(seatID, count):
            mutate(&next, seatID) { $0.handCount = count }

        case let .privateHand(seatID, cards):
            if seatID == next.heroSeatID { next.heroHand = cards.sorted(by: cardDisplayOrder) }

        case let .turnBegan(seatID):
            next.activeSeatID = seatID

        case let .botThinkingBegan(seatID, _):
            mutate(&next, seatID) { $0.isThinking = true }

        case let .botThinkingEnded(seatID):
            mutate(&next, seatID) { $0.isThinking = false }

        case let .tableChanged(_, table, _, _):
            next.melds = table

        case let .playerDrew(_, stockCount):
            next.stockCount = stockCount

        case let .privateDraw(seatID, card):
            if seatID == next.heroSeatID {
                var hand = next.heroHand ?? []
                hand.append(card)
                next.heroHand = hand.sorted(by: cardDisplayOrder)
            }

        case let .turnEnded(seatID, _, handCount):
            mutate(&next, seatID) { $0.handCount = handCount }
            if next.activeSeatID == seatID { next.activeSeatID = nil }

        case let .playerWentOut(seatID):
            mutate(&next, seatID) { $0.wentOut = true }

        case let .handEnded(_, _, handScores, cumulative):
            next.lastHandScores = handScores
            for (id, total) in cumulative { mutate(&next, id) { $0.score = total } }

        case let .matchEnded(_, _, finalScores):
            for (id, total) in finalScores { mutate(&next, id) { $0.score = total } }

        case .sessionEnded:
            next.phase = .finished
        }
        return next
    }

    private static func mutate(_ state: inout MachiavelliTableState, _ id: Int,
                               _ change: (inout MachiavelliSeatPresentation) -> Void) {
        guard let index = state.seats.firstIndex(where: { $0.id == id }) else { return }
        change(&state.seats[index])
    }
}

/// A stable, predictable display order for a hand/table so a blind player can SEARCH a
/// large state without a glance (D-072): by suit, then ascending rank (ace high).
func cardDisplayOrder(_ a: Card, _ b: Card) -> Bool {
    (a.suit.rawValue, a.rank.rawValue) < (b.suit.rawValue, b.rank.rawValue)
}
