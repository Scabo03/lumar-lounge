// TableReducer.swift
// =====================================================================
// Pure state reduction: fold a `SessionEvent` payload into the next
// `TableState`. This is the whole "logic" of the UI layer — and it is only
// PRESENTATION logic (what to show), never GAME logic (that lives in
// GameWorld/GameEngine). Being pure and SwiftUI-free, it is fully unit-testable
// (D-017).

import Foundation
import GameWorld
import GameEngine

public enum TableReducer {

    /// Returns the state after applying one event payload.
    public static func reduce(_ state: TableState, _ payload: EventPayload) -> TableState {
        var next = state
        switch payload {

        case let .sessionBegan(seats, _, _):
            next.seats = seats
                .sorted { $0.position < $1.position }
                .map { SeatPresentation(id: $0.seatID, position: $0.position, chips: $0.chips) }
            next.phase = .playing

        case let .playerJoined(playerID, position, chips):
            if !next.seats.contains(where: { $0.id == playerID }) {
                next.seats.append(SeatPresentation(id: playerID, position: position, chips: chips))
                next.seats.sort { $0.position < $1.position }
            }

        case let .playerLeft(playerID):
            next.seats.removeAll { $0.id == playerID }

        case let .handBegan(handNumber, _, buttonSeatID, smallBlindSeatID, bigBlindSeatID, _, _, seats):
            next.handNumber = handNumber
            next.board = []
            next.pot = 0
            next.buttonSeatID = buttonSeatID
            next.smallBlindSeatID = smallBlindSeatID
            next.bigBlindSeatID = bigBlindSeatID
            next.lastAction = nil
            next.lastStreet = nil
            next.winnerSeatID = nil
            for snapshot in seats {
                mutate(&next, snapshot.seatID) {
                    $0.chips = snapshot.chips
                    $0.isFolded = false
                    $0.isAllIn = false
                    $0.hasCards = false
                    $0.revealedHole = nil
                    $0.isButton = snapshot.seatID == buttonSeatID
                }
            }

        case let .blindPosted(seatID, _, amount, isAllIn):
            mutate(&next, seatID) {
                $0.chips -= amount
                if isAllIn { $0.isAllIn = true }
            }
            next.pot += amount

        case let .holeCardsDealt(seatID):
            mutate(&next, seatID) { $0.hasCards = true }

        case .privateHoleCards:
            break // a spectator never receives these

        case let .playerActed(seatID, action):
            next.lastAction = LastAction(seatID: seatID, action: action)
            switch action {
            case .folded:
                mutate(&next, seatID) { $0.isFolded = true; $0.hasCards = false }
            case .checked:
                break
            case let .called(amount, isAllIn):
                commit(&next, seatID, amount, isAllIn)
            case let .bet(_, amount, isAllIn):
                commit(&next, seatID, amount, isAllIn)
            case let .raised(_, amount, isAllIn):
                commit(&next, seatID, amount, isAllIn)
            }

        case let .streetOpened(street, cards):
            next.board += cards
            next.lastStreet = street

        case let .handShown(seatID, holeCards, _, _):
            mutate(&next, seatID) { $0.revealedHole = holeCards }

        case .potAwarded:
            break // reflected by the chip totals in `handEnded`

        case let .handEnded(_, _, board, _, chips):
            next.board = board
            for (id, amount) in chips { mutate(&next, id) { $0.chips = amount } }

        case let .playerBusted(playerID):
            mutate(&next, playerID) { $0.isBusted = true; $0.hasCards = false }

        case .sessionEnded:
            next.phase = .finished
            next.winnerSeatID = next.seats.first { $0.chips > 0 }?.id
        }
        return next
    }

    // MARK: - Helpers

    private static func mutate(_ state: inout TableState, _ id: Int, _ change: (inout SeatPresentation) -> Void) {
        guard let index = state.seats.firstIndex(where: { $0.id == id }) else { return }
        change(&state.seats[index])
    }

    private static func commit(_ state: inout TableState, _ id: Int, _ amount: Int, _ isAllIn: Bool) {
        mutate(&state, id) {
            $0.chips -= amount
            if isAllIn { $0.isAllIn = true }
        }
        state.pot += amount
    }
}
