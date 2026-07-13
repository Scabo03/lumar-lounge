// OmahaSessionEvent.swift
// =====================================================================
// The observable "voice" of the Omaha session driver: a value-typed, chronological
// stream of everything significant during a session. Distinct taxonomy from Texas
// (`SessionEvent`) and Draw (`DrawSessionEvent`) — the games have different
// vocabularies (Omaha adds a stakes-escalation moment; it has no draw/pass-and-out)
// — but it reuses the game-agnostic `EventAudience`/`EventViewer` routing (D-015).
//
// Events are DESCRIPTIVE (what happened), never PRESCRIPTIVE (never a ritmo/sound).
// Public vs private is by audience: a private event (a player's own four hole cards)
// is addressed to that single player; a viewer subscribing as a player receives
// public events plus only its OWN private events. GameWorld only.

import Foundation
import GameEngine

/// A minimal public snapshot of a seated player at a moment in time.
public struct OmahaSeatSnapshot: Equatable, Sendable {
    public let seatID: Int
    public let position: Int
    public let chips: Int
    public init(seatID: Int, position: Int, chips: Int) {
        self.seatID = seatID
        self.position = position
        self.chips = chips
    }
}

/// Which blind was posted.
public enum OmahaBlindKind: Equatable, Sendable { case small, big }

/// A player's action as observed at the table: what they did and for how much.
/// Self-contained (carries the concrete amounts) so a listener never reconstructs.
public enum OmahaActedAction: Equatable, Sendable {
    case folded
    case checked
    case called(amount: Int, isAllIn: Bool)
    case bet(to: Int, amount: Int, isAllIn: Bool)
    case raised(to: Int, amount: Int, isAllIn: Bool)
}

/// Why a session ended (the caller decides *when*; this says *why*).
public enum OmahaSessionEndReason: Equatable, Sendable { case stopped, notEnoughPlayers }

/// One thing that happened during the session, addressed to an audience and numbered.
public struct OmahaSessionEvent: Equatable, Sendable {
    public let sequence: Int
    public let audience: EventAudience
    public let payload: OmahaEventPayload

    public init(sequence: Int, audience: EventAudience, payload: OmahaEventPayload) {
        self.sequence = sequence
        self.audience = audience
        self.payload = payload
    }
}

/// The taxonomy of significant Omaha moments. Descriptive only.
public enum OmahaEventPayload: Equatable, Sendable {

    // Session lifecycle
    case sessionBegan(seats: [OmahaSeatSnapshot], smallBlind: Int, bigBlind: Int)
    case sessionEnded(reason: OmahaSessionEndReason)

    // Between-hands structural changes
    case playerJoined(playerID: Int, position: Int, chips: Int)
    case playerLeft(playerID: Int)

    // Start of a hand
    case handBegan(handNumber: Int,
                   buttonPosition: Int,
                   buttonSeatID: Int,
                   smallBlindSeatID: Int,
                   bigBlindSeatID: Int,
                   smallBlind: Int,
                   bigBlind: Int,
                   seats: [OmahaSeatSnapshot])
    /// The stakes escalated at the start of this hand (session acceleration, D-064).
    /// Emitted before the blinds when the escalation level increased.
    case stakesEscalated(smallBlind: Int, bigBlind: Int, level: Int)
    case blindPosted(seatID: Int, blind: OmahaBlindKind, amount: Int, isAllIn: Bool)

    /// Public: seat X received its four hole cards (values withheld).
    case holeCardsDealt(seatID: Int)
    /// Private (audience `.player(seatID)`): the seat's own four cards.
    case privateHoleCards(seatID: Int, cards: [Card])

    // Betting
    case playerActed(seatID: Int, action: OmahaActedAction)
    /// A new street's community cards were revealed (flop/turn/river).
    case streetOpened(street: OmahaStreet, communityCards: [Card])

    // Showdown & resolution
    /// A seat revealed its four cards at showdown, with the category and best five of
    /// its CONSTRAINED (two hole + three board) hand.
    case handShown(seatID: Int, holeCards: [Card], category: HandCategory, bestFive: [Card])
    /// A pot (main or side, by index) was awarded to one or more winners.
    case potAwarded(potIndex: Int, amount: Int, winnerSeatIDs: [Int])

    // End of a hand
    case handEnded(handNumber: Int,
                   wentToShowdown: Bool,
                   board: [Card],
                   payouts: [Int: Int],
                   chips: [Int: Int])
    case playerBusted(playerID: Int)
}
