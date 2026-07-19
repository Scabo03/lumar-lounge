// BlackjackReadout.swift
// =====================================================================
// The DETAIL the essential announcement deliberately leaves out — reachable
// on demand, never pushed.
//
// The compact deal line (D-091) gives the player their total and the dealer's
// up card, because that is what a decision needs. It does NOT list the cards
// that make up the total: hearing "ace of spades, six of hearts" every single
// round is a tax the sighted player never pays, since they take the whole
// table in at a glance.
//
// So the cards live here, on accessible elements the player swipes to when
// they want them — the same "interrogate a public state on command" pattern
// the Stud uses for opponent boards (D-078), and the same ordering rule:
// what is needed most often comes FIRST (D-083). At a blackjack table that
// is the total, so every readout leads with it and the card list follows.
//
// Pure and localization-seamed, so the whole thing is unit-testable.

import Foundation
import GameEngine

enum BlackjackReadout {

    typealias Localizer = (String, [CVarArg]) -> String
    private static let standard: Localizer = { uiLocalizedList($0, $1) }

    /// A card in full — rank AND suit — rendered through the seam.
    ///
    /// The suit is irrelevant to blackjack and is therefore kept OUT of the
    /// lines the player hears every round (`BlackjackSpeechMap.spokenRank`).
    /// Here, on the elements the player reaches for deliberately, it goes back
    /// in: a sighted player can see the suits, so they must be available to
    /// everyone — just not imposed on everyone.
    private static func spoken(_ card: Card, _ localized: Localizer) -> String {
        let rank = localized("card.rank.\(card.rank.rawValue)", [])
        let suit = localized("card.suit.\(CardText.suitKey(card.suit))", [])
        return localized("card.spoken.format", [rank, suit])
    }

    private static func spoken(_ cards: [Card], _ localized: Localizer) -> String {
        cards.map { spoken($0, localized) }.joined(separator: ", ")
    }

    /// The player's hand: total first, then the cards it is made of.
    static func hand(_ hand: BlackjackHandPresentation,
                     index: Int,
                     handCount: Int,
                     localized: Localizer = standard) -> String {
        let total = totalPhrase(hand.total, hand.isSoft, localized: localized)
        let cards = spoken(hand.cards, localized)

        if handCount > 1 {
            return localized("blackjack.hero.hand.multi.a11y", [index + 1, handCount, total, cards])
        }
        return localized("blackjack.hero.hand.a11y", [total, cards])
    }

    /// The dealer: while the hole card is down there is exactly one card to
    /// report, and saying so plainly is the whole of it — a face-down card is
    /// face down by the structure of the game and does not need announcing
    /// every time (D-089).
    static func dealer(cards: [Card],
                       holeCardHidden: Bool,
                       hasNatural: Bool = false,
                       didBust: Bool = false,
                       localized: Localizer = standard) -> String {
        guard let up = cards.first else {
            return localized("blackjack.dealer.empty.a11y", [])
        }
        if holeCardHidden {
            return localized("blackjack.dealer.a11y", [spoken(up, localized)])
        }
        let total = BlackjackValue.total(cards)
        if didBust {
            return localized("blackjack.dealer.bust.a11y", [total.total, spoken(cards, localized)])
        }
        let phrase = totalPhrase(total.total, total.isSoft, localized: localized)
        return localized("blackjack.dealer.full.a11y", [phrase, spoken(cards, localized)])
    }

    /// The money on the table: fiches held and the wager riding.
    static func stakes(chips: Int, atStake: Int, localized: Localizer = standard) -> String {
        atStake > 0
            ? localized("blackjack.stakes.a11y", [chips, atStake])
            : localized("blackjack.chips.a11y", [chips])
    }

    static func totalPhrase(_ total: Int, _ isSoft: Bool, localized: Localizer = standard) -> String {
        isSoft ? localized("blackjack.total.soft", [total])
               : localized("blackjack.total.hard", [total])
    }
}
