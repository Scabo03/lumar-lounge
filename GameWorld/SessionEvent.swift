// SessionEvent.swift
// =====================================================================
// The observable "voice" of the session driver: a value-typed, chronological
// stream of everything significant that happens while hands are played, so that
// future consumers (UI, Audio, VoiceOver) can react — without the driver
// knowing they exist (D-015).
//
// Events are DESCRIPTIVE (they say what happened), never PRESCRIPTIVE (they
// never tell anyone what to do). They are pure values (enums/structs), safe to
// pass across concurrent contexts and easy to test. No timing/rhythm lives here:
// the stream runs at code speed; human pacing is the consumer's job.
//
// Public vs private: a `SessionEvent` names its `audience`. Public events go to
// everyone; a private event (a player's own hole cards) is addressed to a single
// player. A viewer subscribing as a specific player receives public events plus
// only its OWN private events — never anyone else's. GameWorld only.

import Foundation
import GameEngine

// MARK: - Audience & viewer

/// Who an event is meant for.
public enum EventAudience: Equatable, Sendable {
    /// Visible to every subscriber.
    case everyone
    /// Visible only to the given player id (e.g. their hole cards).
    case player(Int)
}

/// The point of view a subscriber watches the stream from.
public enum EventViewer: Equatable, Sendable {
    /// Public events only (a spectator, or a generic UI/audio consumer).
    case spectator
    /// Public events plus this player's own private events.
    case player(Int)
}

// MARK: - Small descriptive helpers

/// A minimal public snapshot of a seated player at a moment in time.
public struct SeatSnapshot: Equatable, Sendable {
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
public enum BlindKind: Equatable, Sendable {
    case small
    case big
}

/// A player's action as observed at the table: what they did and for how much.
/// Self-contained (carries the concrete amounts) so a listener never has to
/// reconstruct the numbers from state.
public enum ActedAction: Equatable, Sendable {
    case folded
    case checked
    /// Matched the current bet by adding `amount` chips.
    case called(amount: Int, isAllIn: Bool)
    /// Opened the betting to a total street bet of `to`, adding `amount` chips.
    case bet(to: Int, amount: Int, isAllIn: Bool)
    /// Raised the bet to a total street bet of `to`, adding `amount` chips.
    case raised(to: Int, amount: Int, isAllIn: Bool)
}

/// Why a session ended (the caller decides *when*; this says *why*).
public enum SessionEndReason: Equatable, Sendable {
    case stopped
    case notEnoughPlayers
}

// MARK: - The event

/// One thing that happened during the session, addressed to an audience and
/// numbered in chronological order.
public struct SessionEvent: Equatable, Sendable {
    public let sequence: Int
    public let audience: EventAudience
    public let payload: EventPayload

    public init(sequence: Int, audience: EventAudience, payload: EventPayload) {
        self.sequence = sequence
        self.audience = audience
        self.payload = payload
    }
}

/// The taxonomy of significant moments. Descriptive only.
public enum EventPayload: Equatable, Sendable {

    // Session lifecycle
    case sessionBegan(seats: [SeatSnapshot], smallBlind: Int, bigBlind: Int)
    case sessionEnded(reason: SessionEndReason)

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
                   seats: [SeatSnapshot])
    case blindPosted(seatID: Int, blind: BlindKind, amount: Int, isAllIn: Bool)

    /// Public: seat X received its two hole cards (values withheld).
    case holeCardsDealt(seatID: Int)
    /// Private (audience `.player(seatID)`): the seat's own two cards.
    case privateHoleCards(seatID: Int, cards: [Card])

    // Betting
    case playerActed(seatID: Int, action: ActedAction)
    /// A new street's community cards were revealed (flop/turn/river).
    case streetOpened(street: Street, communityCards: [Card])

    // Showdown & resolution
    /// A seat revealed its cards at showdown, with the category of its best hand.
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
