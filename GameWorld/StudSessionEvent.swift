// StudSessionEvent.swift
// =====================================================================
// The observable "voice" of the Stud session driver: a value-typed, chronological
// stream of everything significant during a session. A distinct taxonomy from the other
// games (D-077): Stud has no community board, an ante + bring-in instead of blinds,
// cards dealt DOWN and UP over five streets, a HOUSE PRIZE (D-078), but no draw or
// escalation-only vocabulary. It reuses the game-agnostic `EventAudience`/`EventViewer`
// routing (D-015).
//
// Events are DESCRIPTIVE (what happened), never PRESCRIPTIVE (never a ritmo/sound).
// Public vs private is by audience: a player's own DOWN cards are addressed to that
// single player; UP cards are public. A viewer subscribing as a player receives public
// events plus only its OWN private events. GameWorld only.

import Foundation
import GameEngine

/// A minimal public snapshot of a seated player at a moment in time.
public struct StudSeatSnapshot: Equatable, Sendable {
    public let seatID: Int
    public let position: Int
    public let chips: Int
    public init(seatID: Int, position: Int, chips: Int) {
        self.seatID = seatID
        self.position = position
        self.chips = chips
    }
}

/// A player's action as observed at the table: what they did and for how much.
/// Self-contained (carries the concrete amounts) so a listener never reconstructs.
public enum StudActedAction: Equatable, Sendable {
    case folded
    case checked
    case called(amount: Int, isAllIn: Bool)
    case bet(to: Int, amount: Int, isAllIn: Bool)
    /// A raise — INCLUDING completing the bring-in to the full bet.
    case raised(to: Int, amount: Int, isAllIn: Bool)
}

/// Why a session ended (the caller decides *when*; this says *why*).
public enum StudSessionEndReason: Equatable, Sendable { case stopped, notEnoughPlayers }

/// One thing that happened during the session, addressed to an audience and numbered.
public struct StudSessionEvent: Equatable, Sendable {
    public let sequence: Int
    public let audience: EventAudience
    public let payload: StudEventPayload

    public init(sequence: Int, audience: EventAudience, payload: StudEventPayload) {
        self.sequence = sequence
        self.audience = audience
        self.payload = payload
    }
}

/// The taxonomy of significant Stud moments. Descriptive only.
public enum StudEventPayload: Equatable, Sendable {

    // Session lifecycle
    case sessionBegan(seats: [StudSeatSnapshot], ante: Int, bringIn: Int, bet: Int)
    case sessionEnded(reason: StudSessionEndReason)

    // Between-hands structural changes
    case playerJoined(playerID: Int, position: Int, chips: Int)
    case playerLeft(playerID: Int)

    // Start of a hand
    case handBegan(handNumber: Int, ante: Int, bringIn: Int, bet: Int, seats: [StudSeatSnapshot])
    case antePosted(seatID: Int, amount: Int, isAllIn: Bool)
    /// Public: seat X received its two face-down cards on third street (values withheld).
    case holeCardsDealt(seatID: Int)
    /// Private (audience `.player(seatID)`): the seat's own down cards (two on third
    /// street, plus the seventh-street card when it arrives).
    case privateDownCards(seatID: Int, cards: [Card])
    /// Public: seat X received a face-UP card on the given street (everyone sees it).
    case upCardDealt(seatID: Int, card: Card, street: StudStreet)
    /// The forced bring-in the low up card had to post on third street.
    case bringInPosted(seatID: Int, amount: Int, isAllIn: Bool)

    // Streets
    /// A new street began (fourth–seventh) — a marker before its cards are dealt.
    case streetBegan(street: StudStreet)
    /// Seventh street dealt a single shared COMMUNITY up card because the deck ran out
    /// (D-077). Rare — only with many players.
    case communityCardDealt(card: Card)

    // Betting
    case playerActed(seatID: Int, action: StudActedAction)

    // Showdown & resolution
    /// A seat revealed all seven cards at showdown, with the category and best five.
    case handShown(seatID: Int, cards: [Card], category: HandCategory, bestFive: [Card])
    /// A pot (main or side, by index) was awarded to one or more winners.
    case potAwarded(potIndex: Int, amount: Int, winnerSeatIDs: [Int])
    /// The HOUSE added a prize to the winning player's pot (D-078) — the ClockTower's
    /// reward for winning the hardest game. Emitted only when the prize recipient won.
    case housePrizeAwarded(playerID: Int, amount: Int)

    // End of a hand
    case handEnded(handNumber: Int, wentToShowdown: Bool, payouts: [Int: Int], chips: [Int: Int])
    case playerBusted(playerID: Int)
}
