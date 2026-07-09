// DrawSessionEvent.swift
// =====================================================================
// The observable "voice" of the Five-Card Draw session driver (D-043): a
// value-typed, chronological stream of everything significant in a draw session,
// so UI / Audio / VoiceOver can react without the driver knowing they exist.
//
// This is a DISTINCT taxonomy from the Texas `SessionEvent` — the two games have
// different vocabularies (ante, draw, pass-and-out, openers, progressive pot), so
// the events are not unified (D-043). It reuses only the game-agnostic `EventAudience`
// and `EventViewer` from the Texas event file (public/private routing, D-015).
//
// Events are DESCRIPTIVE, never PRESCRIPTIVE. Public vs private: a player's own
// dealt/drawn cards are private (audience `.player(id)`); everything else public.
// GameWorld only.

import Foundation
import GameEngine

// MARK: - Small descriptive helpers

/// A minimal public snapshot of a seated player at a draw table.
public struct DrawSeatSnapshot: Equatable, Sendable {
    public let seatID: Int
    public let position: Int
    public let chips: Int

    public init(seatID: Int, position: Int, chips: Int) {
        self.seatID = seatID
        self.position = position
        self.chips = chips
    }
}

/// Which betting round an action happened in.
public enum DrawRound: Equatable, Sendable {
    /// Before the draw (small-bet limit).
    case first
    /// After the draw (big-bet limit).
    case second
}

/// A player's limit-betting action as observed at the table: what they did and
/// how many chips it committed. Self-contained so a listener needn't reconstruct
/// numbers from state.
public enum DrawActedAction: Equatable, Sendable {
    case folded
    case checked
    case called(amount: Int, isAllIn: Bool)
    /// Opened the pot for one bet unit, committing `amount` chips.
    case bet(amount: Int, isAllIn: Bool)
    /// Raised by one bet unit, committing `amount` chips.
    case raised(amount: Int, isAllIn: Bool)
}

/// Why a draw session ended.
public enum DrawSessionEndReason: Equatable, Sendable {
    case stopped
    case notEnoughPlayers
}

// MARK: - The event

/// One thing that happened during a draw session, addressed to an audience and
/// numbered in chronological order.
public struct DrawSessionEvent: Equatable, Sendable {
    public let sequence: Int
    public let audience: EventAudience
    public let payload: DrawEventPayload

    public init(sequence: Int, audience: EventAudience, payload: DrawEventPayload) {
        self.sequence = sequence
        self.audience = audience
        self.payload = payload
    }
}

/// The taxonomy of significant moments in a Five-Card Draw deal. Descriptive only.
public enum DrawEventPayload: Equatable, Sendable {

    // Session lifecycle
    case sessionBegan(seats: [DrawSeatSnapshot], ante: Int, smallBet: Int, bigBet: Int)
    case sessionEnded(reason: DrawSessionEndReason)

    // Between-deal structural changes
    case playerJoined(playerID: Int, position: Int, chips: Int)
    case playerLeft(playerID: Int)

    // Start of a deal
    case handBegan(handNumber: Int,
                   buttonPosition: Int,
                   buttonSeatID: Int,
                   ante: Int,
                   smallBet: Int,
                   bigBet: Int,
                   carriedPot: Int,
                   seats: [DrawSeatSnapshot])
    /// A seat posted its ante (all-in for less if short).
    case antePosted(seatID: Int, amount: Int, isAllIn: Bool)

    /// Public: seat X received its five cards (values withheld).
    case cardsDealt(seatID: Int)
    /// Private (audience `.player(seatID)`): the seat's own five cards.
    case privateCards(seatID: Int, cards: [Card])

    // Betting
    case playerActed(seatID: Int, action: DrawActedAction, round: DrawRound)
    /// A seat opened the pot (the first voluntary bet of round one). `hasOpeners`
    /// records whether it actually held jacks-or-better at that moment (D-039).
    case potOpened(seatID: Int, hasOpeners: Bool)

    // Pass-and-out (progressive pot, D-040)
    /// No one opened: the deal is void, its antes carry into `carriedPot`.
    case passedIn(carriedPot: Int, consecutivePassed: Int)

    // The draw
    case drawPhaseBegan
    /// Public: seat X exchanged `discardCount` cards (which cards stay private).
    case playerDrew(seatID: Int, discardCount: Int)
    /// Private (audience `.player(seatID)`): the seat's own five cards after the draw.
    case privateDrawnCards(seatID: Int, cards: [Card])
    case secondBetBegan

    // Showdown & resolution
    /// A seat revealed its five cards at showdown, with its best-hand category.
    case handShown(seatID: Int, cards: [Card], category: HandCategory, bestFive: [Card])
    /// The opener reached showdown but could not prove openers → disqualified (D-039).
    case openersDisqualified(seatID: Int)
    case potAwarded(potIndex: Int, amount: Int, winnerSeatIDs: [Int])

    // End of a deal
    case handEnded(handNumber: Int,
                   outcome: DrawOutcome,
                   chips: [Int: Int])
    case playerBusted(playerID: Int)
}
