// TableState.swift
// =====================================================================
// The pure presentation state of the poker table: a plain value the view
// renders and the reducer evolves. No SwiftUI, no localization, no game logic —
// just what the table currently looks like (D-017). The UI listens and shows;
// it never decides.

import Foundation
import GameWorld
import GameEngine

/// How one seat currently appears at the table.
public struct SeatPresentation: Equatable, Sendable {
    public let id: Int
    public let position: Int
    public var chips: Int
    public var isFolded: Bool
    public var isAllIn: Bool
    public var isButton: Bool
    /// Whether the seat is holding (face-down) cards this hand.
    public var hasCards: Bool
    /// The seat's cards once revealed at showdown (public), else nil.
    public var revealedHole: [Card]?
    public var isBusted: Bool

    public init(id: Int, position: Int, chips: Int, isFolded: Bool = false, isAllIn: Bool = false,
                isButton: Bool = false, hasCards: Bool = false, revealedHole: [Card]? = nil,
                isBusted: Bool = false) {
        self.id = id
        self.position = position
        self.chips = chips
        self.isFolded = isFolded
        self.isAllIn = isAllIn
        self.isButton = isButton
        self.hasCards = hasCards
        self.revealedHole = revealedHole
        self.isBusted = isBusted
    }
}

/// The most recent action, kept for a transient highlight/caption.
public struct LastAction: Equatable, Sendable {
    public let seatID: Int
    public let action: ActedAction
    public init(seatID: Int, action: ActedAction) {
        self.seatID = seatID
        self.action = action
    }
}

/// The lifecycle phase of the demo table.
public enum TablePhase: Equatable, Sendable {
    case idle
    case playing
    case finished
}

/// Everything the table view needs to draw itself.
public struct TableState: Equatable, Sendable {
    public var seats: [SeatPresentation]
    public var board: [Card]
    public var pot: Int
    public var buttonSeatID: Int?
    public var smallBlindSeatID: Int?
    public var bigBlindSeatID: Int?
    public var handNumber: Int?
    public var phase: TablePhase
    public var lastAction: LastAction?
    public var lastStreet: Street?
    public var winnerSeatID: Int?
    /// The seat id of the human player (its zone is the bottom of the screen).
    public var heroSeatID: Int?
    /// The human's own two hole cards this hand (nil until dealt, or after muck).
    public var heroHole: [Card]?
    /// The seat currently acting / to act (drives the "turn" highlight).
    public var activeSeatID: Int?

    public init(seats: [SeatPresentation] = [], board: [Card] = [], pot: Int = 0,
                buttonSeatID: Int? = nil, smallBlindSeatID: Int? = nil, bigBlindSeatID: Int? = nil,
                handNumber: Int? = nil, phase: TablePhase = .idle, lastAction: LastAction? = nil,
                lastStreet: Street? = nil, winnerSeatID: Int? = nil,
                heroSeatID: Int? = nil, heroHole: [Card]? = nil, activeSeatID: Int? = nil) {
        self.seats = seats
        self.board = board
        self.pot = pot
        self.buttonSeatID = buttonSeatID
        self.smallBlindSeatID = smallBlindSeatID
        self.bigBlindSeatID = bigBlindSeatID
        self.handNumber = handNumber
        self.phase = phase
        self.lastAction = lastAction
        self.lastStreet = lastStreet
        self.winnerSeatID = winnerSeatID
        self.heroSeatID = heroSeatID
        self.heroHole = heroHole
        self.activeSeatID = activeSeatID
    }

    /// The empty starting state.
    public static let empty = TableState()

    public func seat(_ id: Int) -> SeatPresentation? { seats.first { $0.id == id } }

    /// The opponents (everyone but the human), in clockwise order.
    public var opponents: [SeatPresentation] {
        seats.filter { $0.id != heroSeatID }.sorted { $0.position < $1.position }
    }
}
