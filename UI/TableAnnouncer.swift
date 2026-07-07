// TableAnnouncer.swift
// =====================================================================
// Turns session events into VoiceOver narration — but only the PERSONAL ones.
//
// Strategy C (D-028): VoiceOver and the croupier have separate, non-overlapping
// domains. The croupier voices the institutional moments (blinds, streets,
// showdown, pot) as recorded audio; opponents' actions carry no announcement at
// all. VoiceOver is reserved for what is personal to the human player and what
// the croupier does not cover: the human's own hole cards, their own action (as
// confirmation), and their own pot win. (Their turn and the final outcome are
// announced directly by the view model — those aren't stream-derivable here.)
//
// Split in two so the semantic decision is testable without localization (D-016):
//   1. `spoken(for:heroSeatID:)` — PURE: maps an event to a `SpokenEvent` (or nil
//      when the moment is not the human's business). Fully unit-testable and the
//      single source of truth for the new rules.
//   2. `text(for:)` — renders a `SpokenEvent` into a localized, Italian-phonetic
//      string via the localization tables.

import Foundation
import GameWorld
import GameEngine

/// A narratable moment that belongs to the human player. Everything else is the
/// croupier's job (or intentionally silent), so it never appears here.
public enum SpokenEvent: Equatable, Sendable {
    /// The human's own two hole cards, at the start of the hand.
    case heroCards([Card])
    /// The human's own action, spoken back as confirmation.
    case heroActed(ActedAction)
    /// The human won (or split) the pot.
    case heroWonPot(amount: Int)
}

public enum TableAnnouncer {

    /// PURE: maps an event to what VoiceOver should speak, or nil when the moment
    /// is institutional (croupier's job), an opponent's action, or otherwise not
    /// personal to the human. This is the whole of strategy C's VoiceOver rules.
    public static func spoken(for payload: EventPayload, heroSeatID: Int) -> SpokenEvent? {
        switch payload {
        case let .privateHoleCards(seatID, cards) where seatID == heroSeatID:
            return .heroCards(cards)
        case let .playerActed(seatID, action) where seatID == heroSeatID:
            return .heroActed(action)
        case let .potAwarded(_, amount, winnerSeatIDs) where winnerSeatIDs.contains(heroSeatID):
            return .heroWonPot(amount: amount)
        default:
            // Blinds, streets, showdown, hand start, opponents' actions, opponents'
            // busts, pot awards to others… all silent for VoiceOver (D-028).
            return nil
        }
    }

    /// Renders a personal moment into a localized, phonetic string.
    public static func text(for spoken: SpokenEvent) -> String {
        switch spoken {
        case let .heroCards(cards):
            return uiLocalized("announce.hero.cards", CardText.spoken(cards))
        case let .heroActed(action):
            return heroActionText(action)
        case let .heroWonPot(amount):
            return uiLocalized("announce.pot.you", amount)
        }
    }

    // MARK: - Fragments

    /// First-person confirmation of the human's own action (phonetic poker terms).
    private static func heroActionText(_ action: ActedAction) -> String {
        switch action {
        case .folded:
            return uiLocalized("announce.you.folded")
        case .checked:
            return uiLocalized("announce.you.checked")
        case let .called(amount, isAllIn):
            return uiLocalized(isAllIn ? "announce.you.called.allin" : "announce.you.called", amount)
        case let .bet(to, _, isAllIn):
            return uiLocalized(isAllIn ? "announce.you.bet.allin" : "announce.you.bet", to)
        case let .raised(to, _, isAllIn):
            return uiLocalized(isAllIn ? "announce.you.raised.allin" : "announce.you.raised", to)
        }
    }
}
