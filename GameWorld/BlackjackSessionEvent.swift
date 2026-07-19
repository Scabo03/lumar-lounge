// BlackjackSessionEvent.swift
// =====================================================================
// What the blackjack driver NARRATES.
//
// Events are DESCRIPTIVE — they say what happened — and never PRESCRIPTIVE:
// nothing here names a sound, a view or a tempo. Consumers (the table view,
// the audio director) decide what to do with them, and the producer never
// knows the human rhythm.
//
// Audience: blackjack has no hidden player information — the player's own
// cards are theirs and the dealer's up card is public. The ONE genuinely
// private thing is the dealer's hole card, which is simply not in any event
// until it is turned over. So every event here is `.everyone`; the audience
// machinery is still carried for uniformity with the other games.

import Foundation
import GameEngine

/// Which of the player's hands an event is about. Blackjack's split means the
/// player can hold several hands at once, so nearly everything is indexed.
public typealias BlackjackHandIndex = Int

public enum BlackjackSessionEndReason: Equatable, Sendable {
    case stopped
    case outOfChips
}

/// The player's move, as it happened.
public enum BlackjackActedAction: Equatable, Sendable {
    case hit(card: Card, total: Int, isSoft: Bool, didBust: Bool)
    case stood(total: Int)
    case doubled(card: Card, total: Int, wager: Int, didBust: Bool)
    /// Carries the WHOLE picture after the split — every hand's cards — because
    /// a listener cannot reconstruct it: the split deals a card to each new hand
    /// at once, and the second hand's cards would otherwise stay unknown until
    /// its turn came round.
    case split(hands: [[Card]], wager: Int)
    case surrendered(refund: Int)
}

public struct BlackjackSessionEvent: Equatable, Sendable {
    public let sequence: Int
    public let audience: EventAudience
    public let payload: BlackjackEventPayload

    public init(sequence: Int, audience: EventAudience, payload: BlackjackEventPayload) {
        self.sequence = sequence
        self.audience = audience
        self.payload = payload
    }
}

public enum BlackjackEventPayload: Equatable, Sendable {

    // Session lifecycle
    case sessionBegan(chips: Int, minimumBet: Int, maximumBet: Int)
    case sessionEnded(reason: BlackjackSessionEndReason)

    /// The dealer reshuffles the shoe. Purely descriptive colour, but a real
    /// event of the game — the player hears it and it explains the pause.
    case shoeShuffled(roundNumber: Int)

    // A round
    case roundBegan(roundNumber: Int, bet: Int, chips: Int)

    /// The deal, delivered as ONE event rather than four.
    ///
    /// This is deliberate and is the heart of the game's accessibility (D-091):
    /// a sighted player takes in both their cards and the dealer's up card in a
    /// single glance, so the blind player receives them as a single fact too,
    /// not as a queue of four separate announcements.
    case dealt(playerCards: [Card], total: Int, isSoft: Bool,
               dealerUpCard: Card, isNatural: Bool)

    /// Which hand the player is now acting on, and what is on the table for it.
    case handTurnBegan(handIndex: BlackjackHandIndex, cards: [Card],
                       total: Int, isSoft: Bool, handCount: Int)

    /// `chips` is the player's REMAINING fiches after the move, so a listener
    /// always knows what is still theirs versus what is on the felt — a double
    /// or a split commits more, and leaving the table mid-round forfeits it
    /// (D-086), which only works if this number is never stale.
    case playerActed(handIndex: BlackjackHandIndex, action: BlackjackActedAction, chips: Int)

    /// The dealer turns the hole card over and plays out, delivered as one
    /// event carrying the whole sequence — again one fact, not a drip feed.
    case dealerPlayed(cards: [Card], total: Int, isSoft: Bool,
                      didBust: Bool, hasNatural: Bool, drew: Bool)

    /// How each hand finished.
    case handSettled(handIndex: BlackjackHandIndex, handCount: Int,
                     outcome: BlackjackOutcome, total: Int, bet: Int, net: Int)

    case roundEnded(roundNumber: Int, net: Int, chips: Int, handCount: Int)
}
