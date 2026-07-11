// DrawTableState.swift
// =====================================================================
// The pure presentation state of the Five-Card Draw table, and the pure reducer
// that folds a `DrawEventPayload` into the next state (D-044). No SwiftUI, no
// localization, no game logic — just what the draw table currently looks like. As
// in the Texas layer (D-017), the UI listens and shows; it never decides.
//
// A dedicated state/reducer (not the Texas `TableState`): the draw table has five
// hero cards, no board, a phase machine (first bet → draw → second bet), a
// progressive carried pot, per-seat discard counts, and opener disqualification.

import Foundation
import GameWorld
import GameEngine

/// How one seat currently appears at the draw table.
public struct DrawSeatPresentation: Equatable, Sendable {
    public let id: Int
    public let position: Int
    public var chips: Int
    public var isFolded: Bool
    public var isAllIn: Bool
    public var isButton: Bool
    public var isOpener: Bool
    /// Holds (face-down) five cards this deal.
    public var hasCards: Bool
    /// How many cards the seat exchanged in the draw (nil until it has drawn).
    public var discardCount: Int?
    /// The seat's five cards, revealed at showdown (public), else nil.
    public var revealed: [Card]?
    public var isBusted: Bool
    /// Disqualified at showdown for opening without provable openers (D-039).
    public var isDisqualified: Bool

    public init(id: Int, position: Int, chips: Int, isFolded: Bool = false, isAllIn: Bool = false,
                isButton: Bool = false, isOpener: Bool = false, hasCards: Bool = false,
                discardCount: Int? = nil, revealed: [Card]? = nil, isBusted: Bool = false,
                isDisqualified: Bool = false) {
        self.id = id
        self.position = position
        self.chips = chips
        self.isFolded = isFolded
        self.isAllIn = isAllIn
        self.isButton = isButton
        self.isOpener = isOpener
        self.hasCards = hasCards
        self.discardCount = discardCount
        self.revealed = revealed
        self.isBusted = isBusted
        self.isDisqualified = isDisqualified
    }
}

/// The lifecycle phase of the draw table.
public enum DrawTablePhase: Equatable, Sendable {
    case idle
    case firstBet
    case draw
    case secondBet
    case finished
}

/// Everything the draw table view needs to draw itself.
public struct DrawTableState: Equatable, Sendable {
    public var seats: [DrawSeatPresentation]
    public var pot: Int
    /// Dead money carried in from prior passed-in deals (progressive pot, D-040).
    public var carriedPot: Int
    public var buttonSeatID: Int?
    public var handNumber: Int?
    public var phase: DrawTablePhase
    public var heroSeatID: Int?
    /// The human's own five cards this deal (nil until dealt, or after fold).
    public var heroCards: [Card]?
    public var activeSeatID: Int?
    /// True right after a deal was passed in (nobody opened), for a transient banner.
    public var passedIn: Bool
    /// The last consecutive-passed count reported (for the banner text).
    public var consecutivePassed: Int
    /// True during a DECISIVE hand (doubled bets, higher cap — D-053), for a banner.
    public var decisive: Bool
    /// The ante posted this deal — grows with the progressive ante (D-052), shown so
    /// the player sees the table getting more expensive after pass-and-outs.
    public var ante: Int

    public init(seats: [DrawSeatPresentation] = [], pot: Int = 0, carriedPot: Int = 0,
                buttonSeatID: Int? = nil, handNumber: Int? = nil, phase: DrawTablePhase = .idle,
                heroSeatID: Int? = nil, heroCards: [Card]? = nil, activeSeatID: Int? = nil,
                passedIn: Bool = false, consecutivePassed: Int = 0, decisive: Bool = false,
                ante: Int = 0) {
        self.seats = seats
        self.pot = pot
        self.carriedPot = carriedPot
        self.buttonSeatID = buttonSeatID
        self.handNumber = handNumber
        self.phase = phase
        self.heroSeatID = heroSeatID
        self.heroCards = heroCards
        self.activeSeatID = activeSeatID
        self.passedIn = passedIn
        self.consecutivePassed = consecutivePassed
        self.decisive = decisive
        self.ante = ante
    }

    public static let empty = DrawTableState()

    public func seat(_ id: Int) -> DrawSeatPresentation? { seats.first { $0.id == id } }

    public var opponents: [DrawSeatPresentation] {
        seats.filter { $0.id != heroSeatID }.sorted { $0.position < $1.position }
    }
}

public enum DrawTableReducer {

    public static func reduce(_ state: DrawTableState, _ payload: DrawEventPayload) -> DrawTableState {
        var next = state
        switch payload {

        case let .sessionBegan(seats, _, _, _):
            next.seats = seats.sorted { $0.position < $1.position }
                .map { DrawSeatPresentation(id: $0.seatID, position: $0.position, chips: $0.chips) }
            next.phase = .idle

        case let .playerJoined(playerID, position, chips):
            if !next.seats.contains(where: { $0.id == playerID }) {
                next.seats.append(DrawSeatPresentation(id: playerID, position: position, chips: chips))
                next.seats.sort { $0.position < $1.position }
            }

        case let .playerLeft(playerID):
            next.seats.removeAll { $0.id == playerID }

        case let .handBegan(handNumber, _, buttonSeatID, ante, _, _, carriedPot, seats):
            next.handNumber = handNumber
            next.ante = ante
            next.pot = carriedPot
            next.carriedPot = carriedPot
            next.buttonSeatID = buttonSeatID
            next.phase = .firstBet
            next.heroCards = nil
            next.activeSeatID = nil
            next.passedIn = false
            next.decisive = false
            for snapshot in seats {
                mutate(&next, snapshot.seatID) {
                    $0.chips = snapshot.chips
                    $0.isFolded = false
                    $0.isAllIn = false
                    $0.isOpener = false
                    $0.hasCards = false
                    $0.discardCount = nil
                    $0.revealed = nil
                    $0.isDisqualified = false
                    $0.isButton = snapshot.seatID == buttonSeatID
                }
            }

        case .decisiveHandStarted:
            next.decisive = true

        case let .antePosted(seatID, amount, isAllIn):
            mutate(&next, seatID) {
                $0.chips -= amount
                if isAllIn { $0.isAllIn = true }
            }
            next.pot += amount

        case let .cardsDealt(seatID):
            mutate(&next, seatID) { $0.hasCards = true }

        case let .privateCards(seatID, cards):
            if seatID == next.heroSeatID { next.heroCards = cards }

        case let .playerActed(seatID, action, _):
            switch action {
            case .folded:
                mutate(&next, seatID) { $0.isFolded = true; $0.hasCards = false }
                if seatID == next.heroSeatID { next.heroCards = nil }
            case .checked:
                break
            case let .called(amount, isAllIn):
                commit(&next, seatID, amount, isAllIn)
            case let .bet(amount, isAllIn):
                commit(&next, seatID, amount, isAllIn)
            case let .raised(amount, isAllIn):
                commit(&next, seatID, amount, isAllIn)
            }

        case let .potOpened(seatID, _):
            mutate(&next, seatID) { $0.isOpener = true }

        case let .passedIn(carriedPot, consecutivePassed):
            next.passedIn = true
            next.carriedPot = carriedPot
            next.consecutivePassed = consecutivePassed

        case .drawPhaseBegan:
            next.phase = .draw

        case let .playerDrew(seatID, discardCount):
            mutate(&next, seatID) { $0.discardCount = discardCount }

        case let .privateDrawnCards(seatID, cards):
            if seatID == next.heroSeatID { next.heroCards = cards }

        case .secondBetBegan:
            next.phase = .secondBet

        case let .handShown(seatID, cards, _, _):
            mutate(&next, seatID) { $0.revealed = cards }

        case let .openersDisqualified(seatID):
            mutate(&next, seatID) { $0.isDisqualified = true }

        case .potAwarded:
            break   // reflected by chip totals in handEnded

        case let .handEnded(_, _, chips):
            for (id, amount) in chips { mutate(&next, id) { $0.chips = amount } }

        case let .playerBusted(playerID):
            mutate(&next, playerID) { $0.isBusted = true; $0.hasCards = false }

        case .sessionEnded:
            next.phase = .finished
        }
        return next
    }

    // MARK: - Helpers

    private static func mutate(_ state: inout DrawTableState, _ id: Int,
                               _ change: (inout DrawSeatPresentation) -> Void) {
        guard let index = state.seats.firstIndex(where: { $0.id == id }) else { return }
        change(&state.seats[index])
    }

    private static func commit(_ state: inout DrawTableState, _ id: Int, _ amount: Int, _ isAllIn: Bool) {
        mutate(&state, id) {
            $0.chips -= amount
            if isAllIn { $0.isAllIn = true }
        }
        state.pot += amount
    }
}
