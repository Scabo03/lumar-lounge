// MachiavelliSessionEvent.swift
// =====================================================================
// The observable "voice" of the Machiavelli session driver: a value-typed,
// chronological stream of everything significant during a game. Its own taxonomy
// (Machiavelli's vocabulary — melds, recomposition, drawing, going out — shares
// nothing with poker's), reusing only the game-agnostic `EventAudience`/`EventViewer`
// routing (D-015).
//
// Events are DESCRIPTIVE (what happened), never PRESCRIPTIVE (never a ritmo/sound).
// Public vs private is by audience: a player's own dealt hand is addressed to that
// single player; everything on the table is public, as are opponents' hand COUNTS.
//
// THE AUDIBLE WAIT (D-070). A bot that reworks the table can deliberate for many
// seconds. For a blind player, seconds of silence read as a frozen game. So the driver
// emits an explicit `botThinkingBegan` (carrying the bot's EXPECTED deliberation, a
// descriptive hint) and `botThinkingEnded` bracketing every bot decision, so a future
// UI/audio can fill that silence. This module produces NO audio and declares no sounds
// — only the events. GameWorld only.

import Foundation
import GameEngine

/// A minimal public snapshot of a seated player at a moment in time.
public struct MachiavelliSeatSnapshot: Equatable, Sendable {
    public let seatID: Int
    public let position: Int
    public let handCount: Int
    public init(seatID: Int, position: Int, handCount: Int) {
        self.seatID = seatID
        self.position = position
        self.handCount = handCount
    }
}

/// How a player ended their turn.
public enum MachiavelliTurnEnding: Equatable, Sendable {
    /// Placed one or more cards and passed. `placed` = the hand cards laid down;
    /// `rearrangedTable` = whether existing combinations were dismantled/recomposed.
    case melded(placed: [Card], rearrangedTable: Bool)
    /// Placed nothing and drew a card from the stock (or, if the stock was empty,
    /// passed without drawing).
    case drew(fromStock: Bool)
}

/// Why a session ended (the caller decides *when*; this says *why*).
public enum MachiavelliSessionEndReason: Equatable, Sendable { case stopped, matchCompleted }

/// One thing that happened during a Machiavelli game, addressed and numbered.
public struct MachiavelliSessionEvent: Equatable, Sendable {
    public let sequence: Int
    public let audience: EventAudience
    public let payload: MachiavelliEventPayload

    public init(sequence: Int, audience: EventAudience, payload: MachiavelliEventPayload) {
        self.sequence = sequence
        self.audience = audience
        self.payload = payload
    }
}

/// The taxonomy of significant Machiavelli moments. Descriptive only.
public enum MachiavelliEventPayload: Equatable, Sendable {

    // Session/match lifecycle
    case sessionBegan(seats: [MachiavelliSeatSnapshot], handSize: Int, victoryThreshold: Int)
    case sessionEnded(reason: MachiavelliSessionEndReason)
    /// A new HAND (single deal) began within the match.
    case handBegan(handNumber: Int, seats: [MachiavelliSeatSnapshot], firstToActSeatID: Int, stockCount: Int)

    // Dealing
    /// Public: seat X was dealt its hand (count only).
    case handDealt(seatID: Int, count: Int)
    /// Private (audience `.player(seatID)`): the seat's own cards.
    case privateHand(seatID: Int, cards: [Card])

    // Turns
    case turnBegan(seatID: Int)
    /// A bot began deliberating; `expectedDeliberation` is a descriptive character hint
    /// so the UI/audio can fill the silence (the audible wait, D-070).
    case botThinkingBegan(seatID: Int, expectedDeliberation: Duration)
    case botThinkingEnded(seatID: Int)
    /// The table changed: the new full arrangement and which hand cards were placed.
    case tableChanged(seatID: Int, table: [[Card]], placed: [Card], rearrangedExisting: Bool)
    /// A player drew a card from the stock (public: a card was drawn; the value is
    /// private to the drawer via `privateDraw`).
    case playerDrew(seatID: Int, stockCount: Int)
    /// Private (audience `.player(seatID)`): the exact card drawn.
    case privateDraw(seatID: Int, card: Card)
    /// A turn ended, with how it ended and the player's new hand count.
    case turnEnded(seatID: Int, ending: MachiavelliTurnEnding, handCount: Int)

    // Resolution
    /// A player emptied their hand (went out), ending the hand.
    case playerWentOut(seatID: Int)
    /// A hand ended (out or stalemate) with the points it awarded and the running
    /// match totals (D-071). `wentOutSeatID` is `nil` for a stalemate.
    case handEnded(handNumber: Int,
                   wentOutSeatID: Int?,
                   handScores: [Int: Int],
                   cumulativeScores: [Int: Int])
    /// A player crossed the victory threshold: the match is over (D-071).
    case matchEnded(winnerID: Int, handsPlayed: Int, finalScores: [Int: Int])
}
