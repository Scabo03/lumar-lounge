// OmahaTableState.swift
// =====================================================================
// The pure presentation state of the Omaha Pot Limit table, and the pure reducer
// that folds an `OmahaEventPayload` into the next state (D-066). No SwiftUI, no
// localization, no game logic — just what the Omaha table currently looks like. As in
// the Texas/Draw layers (D-017), the UI listens and shows; it never decides.
//
// A dedicated state/reducer (not the Texas `TableState`): Omaha deals FOUR hole cards,
// runs the four community streets, uses Pot Limit betting and a stake escalation
// (D-064). The events differ from Texas (`OmahaEventPayload`), so the reducer is its own.

import Foundation
import GameWorld
import GameEngine

/// How one seat currently appears at the Omaha table.
public struct OmahaSeatPresentation: Equatable, Sendable {
    public let id: Int
    public let position: Int
    public var chips: Int
    public var isFolded: Bool
    public var isAllIn: Bool
    public var isButton: Bool
    /// Holds (face-down) four cards this hand.
    public var hasCards: Bool
    /// The seat's four cards, revealed at showdown (public), else nil.
    public var revealed: [Card]?
    public var isBusted: Bool

    public init(id: Int, position: Int, chips: Int, isFolded: Bool = false, isAllIn: Bool = false,
                isButton: Bool = false, hasCards: Bool = false, revealed: [Card]? = nil, isBusted: Bool = false) {
        self.id = id
        self.position = position
        self.chips = chips
        self.isFolded = isFolded
        self.isAllIn = isAllIn
        self.isButton = isButton
        self.hasCards = hasCards
        self.revealed = revealed
        self.isBusted = isBusted
    }
}

/// Everything the Omaha table view needs to draw itself.
public struct OmahaTableState: Equatable, Sendable {
    public var seats: [OmahaSeatPresentation]
    public var board: [Card]
    public var pot: Int
    public var buttonSeatID: Int?
    public var handNumber: Int?
    public var heroSeatID: Int?
    /// The human's own four cards this hand (nil until dealt, or after fold).
    public var heroCards: [Card]?
    public var activeSeatID: Int?
    /// The blinds this hand is played at — grow with the stake escalation (D-064).
    public var smallBlind: Int
    public var bigBlind: Int
    /// True right after the stakes escalated, for a transient banner (D-064).
    public var escalated: Bool
    public var finished: Bool

    public init(seats: [OmahaSeatPresentation] = [], board: [Card] = [], pot: Int = 0,
                buttonSeatID: Int? = nil, handNumber: Int? = nil, heroSeatID: Int? = nil,
                heroCards: [Card]? = nil, activeSeatID: Int? = nil, smallBlind: Int = 0,
                bigBlind: Int = 0, escalated: Bool = false, finished: Bool = false) {
        self.seats = seats
        self.board = board
        self.pot = pot
        self.buttonSeatID = buttonSeatID
        self.handNumber = handNumber
        self.heroSeatID = heroSeatID
        self.heroCards = heroCards
        self.activeSeatID = activeSeatID
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.escalated = escalated
        self.finished = finished
    }

    public static let empty = OmahaTableState()

    public func seat(_ id: Int) -> OmahaSeatPresentation? { seats.first { $0.id == id } }

    public var opponents: [OmahaSeatPresentation] {
        seats.filter { $0.id != heroSeatID }.sorted { $0.position < $1.position }
    }
}

public enum OmahaTableReducer {

    public static func reduce(_ state: OmahaTableState, _ payload: OmahaEventPayload) -> OmahaTableState {
        var next = state
        switch payload {

        case let .sessionBegan(seats, sb, bb):
            next.seats = seats.sorted { $0.position < $1.position }
                .map { OmahaSeatPresentation(id: $0.seatID, position: $0.position, chips: $0.chips) }
            next.smallBlind = sb
            next.bigBlind = bb

        case let .playerJoined(playerID, position, chips):
            if !next.seats.contains(where: { $0.id == playerID }) {
                next.seats.append(OmahaSeatPresentation(id: playerID, position: position, chips: chips))
                next.seats.sort { $0.position < $1.position }
            }

        case let .playerLeft(playerID):
            next.seats.removeAll { $0.id == playerID }

        case let .handBegan(handNumber, _, buttonSeatID, _, _, sb, bb, seats):
            next.handNumber = handNumber
            next.board = []
            next.pot = 0
            next.buttonSeatID = buttonSeatID
            next.smallBlind = sb
            next.bigBlind = bb
            next.heroCards = nil
            next.activeSeatID = nil
            next.escalated = false
            for snapshot in seats {
                mutate(&next, snapshot.seatID) {
                    $0.chips = snapshot.chips
                    $0.isFolded = false
                    $0.isAllIn = false
                    $0.hasCards = false
                    $0.revealed = nil
                    $0.isButton = snapshot.seatID == buttonSeatID
                }
            }

        case let .stakesEscalated(sb, bb, _):
            next.smallBlind = sb
            next.bigBlind = bb
            next.escalated = true

        case let .blindPosted(seatID, _, amount, isAllIn):
            mutate(&next, seatID) {
                $0.chips -= amount
                if isAllIn { $0.isAllIn = true }
            }
            next.pot += amount

        case let .holeCardsDealt(seatID):
            mutate(&next, seatID) { $0.hasCards = true }

        case let .privateHoleCards(seatID, cards):
            if seatID == next.heroSeatID { next.heroCards = cards }

        case let .playerActed(seatID, action):
            switch action {
            case .folded:
                mutate(&next, seatID) { $0.isFolded = true; $0.hasCards = false }
                if seatID == next.heroSeatID { next.heroCards = nil }
            case .checked:
                break
            case let .called(amount, isAllIn):
                commit(&next, seatID, amount, isAllIn)
            case let .bet(_, amount, isAllIn):
                commit(&next, seatID, amount, isAllIn)
            case let .raised(_, amount, isAllIn):
                commit(&next, seatID, amount, isAllIn)
            }

        case let .streetOpened(_, communityCards):
            next.board += communityCards

        case let .handShown(seatID, holeCards, _, _):
            mutate(&next, seatID) { $0.revealed = holeCards }

        case .potAwarded:
            break   // reflected by chip totals in handEnded

        case let .handEnded(_, _, board, _, chips):
            next.board = board
            for (id, amount) in chips { mutate(&next, id) { $0.chips = amount } }

        case let .playerBusted(playerID):
            mutate(&next, playerID) { $0.isBusted = true; $0.hasCards = false }

        case .sessionEnded:
            next.finished = true
        }
        return next
    }

    // MARK: - Helpers

    private static func mutate(_ state: inout OmahaTableState, _ id: Int,
                               _ change: (inout OmahaSeatPresentation) -> Void) {
        guard let index = state.seats.firstIndex(where: { $0.id == id }) else { return }
        change(&state.seats[index])
    }

    private static func commit(_ state: inout OmahaTableState, _ id: Int, _ amount: Int, _ isAllIn: Bool) {
        mutate(&state, id) {
            $0.chips -= amount
            if isAllIn { $0.isAllIn = true }
        }
        state.pot += amount
    }
}
