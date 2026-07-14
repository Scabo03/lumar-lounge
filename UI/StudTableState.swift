// StudTableState.swift
// =====================================================================
// The pure presentation state of the Seven-Card Stud Pot Limit table, and the pure
// reducer that folds a `StudEventPayload` into the next state (D-077). No SwiftUI, no
// localization, no game logic — just what the Stud table currently looks like. As in the
// other UI layers (D-017), the UI listens and shows; it never decides.
//
// The defining Stud element carried here is each seat's UP CARDS — the public,
// per-player boards that are the strategic heart of the game and the accessibility
// challenge (D-077): a blind player can't hold three opponents' boards in memory, so the
// state keeps every seat's current up cards for the on-demand interrogation the view
// exposes (D-078).

import Foundation
import GameWorld
import GameEngine

/// How one seat currently appears at the Stud table.
public struct StudSeatPresentation: Equatable, Sendable {
    public let id: Int
    public let position: Int
    public var chips: Int
    public var isFolded: Bool
    public var isAllIn: Bool
    /// Holds face-down cards this hand (for the down-card backs).
    public var hasCards: Bool
    /// The seat's face-UP cards, dealt over the streets — PUBLIC (everyone sees them).
    public var upCards: [Card]
    /// The seat's brought-in this hand (a subtle marker on third street).
    public var isBringIn: Bool
    /// All seven cards revealed at showdown (public), else nil.
    public var revealed: [Card]?
    public var isBusted: Bool

    public init(id: Int, position: Int, chips: Int, isFolded: Bool = false, isAllIn: Bool = false,
                hasCards: Bool = false, upCards: [Card] = [], isBringIn: Bool = false,
                revealed: [Card]? = nil, isBusted: Bool = false) {
        self.id = id
        self.position = position
        self.chips = chips
        self.isFolded = isFolded
        self.isAllIn = isAllIn
        self.hasCards = hasCards
        self.upCards = upCards
        self.isBringIn = isBringIn
        self.revealed = revealed
        self.isBusted = isBusted
    }
}

/// Everything the Stud table view needs to draw itself.
public struct StudTableState: Equatable, Sendable {
    public var seats: [StudSeatPresentation]
    public var pot: Int
    public var ante: Int
    public var bringIn: Int
    public var bet: Int
    public var street: StudStreet?
    public var handNumber: Int?
    public var heroSeatID: Int?
    /// The human's own DOWN cards this hand (nil until dealt, or after fold): two on third
    /// street, three by seventh.
    public var heroDown: [Card]?
    public var activeSeatID: Int?
    /// The shared community card, if the deck was exhausted on seventh street (rare).
    public var communityCard: Card?
    /// The house prize just awarded to the human, for a transient banner (D-078).
    public var housePrizeAwarded: Int
    public var finished: Bool

    public init(seats: [StudSeatPresentation] = [], pot: Int = 0, ante: Int = 0, bringIn: Int = 0,
                bet: Int = 0, street: StudStreet? = nil, handNumber: Int? = nil, heroSeatID: Int? = nil,
                heroDown: [Card]? = nil, activeSeatID: Int? = nil, communityCard: Card? = nil,
                housePrizeAwarded: Int = 0, finished: Bool = false) {
        self.seats = seats
        self.pot = pot
        self.ante = ante
        self.bringIn = bringIn
        self.bet = bet
        self.street = street
        self.handNumber = handNumber
        self.heroSeatID = heroSeatID
        self.heroDown = heroDown
        self.activeSeatID = activeSeatID
        self.communityCard = communityCard
        self.housePrizeAwarded = housePrizeAwarded
        self.finished = finished
    }

    public func seat(_ id: Int) -> StudSeatPresentation? { seats.first { $0.id == id } }

    public var opponents: [StudSeatPresentation] {
        seats.filter { $0.id != heroSeatID }.sorted { $0.position < $1.position }
    }

    /// The hero's own seven-in-progress cards (down + up), for the hero zone.
    public var heroCards: [Card]? {
        guard let heroSeatID, let down = heroDown, let seat = seat(heroSeatID) else { return nil }
        return down + seat.upCards
    }
}

public enum StudTableReducer {

    public static func reduce(_ state: StudTableState, _ payload: StudEventPayload) -> StudTableState {
        var next = state
        switch payload {

        case let .sessionBegan(seats, ante, bringIn, bet):
            next.seats = seats.sorted { $0.position < $1.position }
                .map { StudSeatPresentation(id: $0.seatID, position: $0.position, chips: $0.chips) }
            next.ante = ante; next.bringIn = bringIn; next.bet = bet

        case let .playerJoined(playerID, position, chips):
            if !next.seats.contains(where: { $0.id == playerID }) {
                next.seats.append(StudSeatPresentation(id: playerID, position: position, chips: chips))
                next.seats.sort { $0.position < $1.position }
            }

        case let .playerLeft(playerID):
            next.seats.removeAll { $0.id == playerID }

        case let .handBegan(handNumber, ante, bringIn, bet, seats):
            next.handNumber = handNumber
            next.pot = 0
            next.ante = ante; next.bringIn = bringIn; next.bet = bet
            next.street = .third
            next.heroDown = nil
            next.activeSeatID = nil
            next.communityCard = nil
            next.housePrizeAwarded = 0
            for snapshot in seats {
                mutate(&next, snapshot.seatID) {
                    $0.chips = snapshot.chips
                    $0.isFolded = false
                    $0.isAllIn = false
                    $0.hasCards = false
                    $0.upCards = []
                    $0.isBringIn = false
                    $0.revealed = nil
                }
            }

        case let .antePosted(seatID, amount, isAllIn):
            mutate(&next, seatID) { $0.chips -= amount; if isAllIn { $0.isAllIn = true } }
            next.pot += amount

        case let .holeCardsDealt(seatID):
            mutate(&next, seatID) { $0.hasCards = true }

        case let .privateDownCards(seatID, cards):
            if seatID == next.heroSeatID {
                if next.heroDown == nil { next.heroDown = cards } else { next.heroDown?.append(contentsOf: cards) }
            }

        case let .upCardDealt(seatID, card, _):
            mutate(&next, seatID) { $0.upCards.append(card); $0.hasCards = true }

        case let .bringInPosted(seatID, amount, isAllIn):
            mutate(&next, seatID) { $0.chips -= amount; $0.isBringIn = true; if isAllIn { $0.isAllIn = true } }
            next.pot += amount

        case let .streetBegan(street):
            next.street = street

        case let .communityCardDealt(card):
            next.communityCard = card

        case let .playerActed(seatID, action):
            switch action {
            case .folded:
                mutate(&next, seatID) { $0.isFolded = true; $0.hasCards = false; $0.upCards = [] }
                if seatID == next.heroSeatID { next.heroDown = nil }
            case .checked:
                break
            case let .called(amount, isAllIn):
                commit(&next, seatID, amount, isAllIn)
            case let .bet(_, amount, isAllIn):
                commit(&next, seatID, amount, isAllIn)
            case let .raised(_, amount, isAllIn):
                commit(&next, seatID, amount, isAllIn)
            }

        case let .handShown(seatID, cards, _, _):
            mutate(&next, seatID) { $0.revealed = cards }

        case .potAwarded:
            break   // reflected by chip totals in handEnded

        case let .housePrizeAwarded(_, amount):
            next.housePrizeAwarded = amount

        case let .handEnded(_, _, _, chips):
            for (id, amount) in chips { mutate(&next, id) { $0.chips = amount } }

        case let .playerBusted(playerID):
            mutate(&next, playerID) { $0.isBusted = true; $0.hasCards = false }

        case .sessionEnded:
            next.finished = true
        }
        return next
    }

    // MARK: - Helpers

    private static func mutate(_ state: inout StudTableState, _ id: Int,
                               _ change: (inout StudSeatPresentation) -> Void) {
        guard let index = state.seats.firstIndex(where: { $0.id == id }) else { return }
        change(&state.seats[index])
    }

    private static func commit(_ state: inout StudTableState, _ id: Int, _ amount: Int, _ isAllIn: Bool) {
        mutate(&state, id) {
            $0.chips -= amount
            if isAllIn { $0.isAllIn = true }
        }
        state.pot += amount
    }
}
