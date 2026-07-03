// Localization.swift
// =====================================================================
// Localized-string helpers for the UI module. Every user-visible string comes
// from the app's localization tables (`Resources/*.lproj`), resolved via the
// main bundle — never hard-coded (CONVENTIONS §3).
//
// Poker terms are rendered PHONETICALLY in Italian inside the `it.lproj`
// strings (e.g. "reis" for raise, "blaind" for blind) so VoiceOver's Italian
// voice pronounces them correctly (CONVENTIONS §4, D-016). The English table
// keeps the normal English spelling.

import Foundation
import GameEngine

/// Looks up a localized string by key from the main bundle.
func uiLocalized(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: "")
}

/// Looks up and formats a localized string with arguments.
func uiLocalized(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, bundle: .main, comment: ""), arguments: args)
}

/// Formats cards for display and for spoken (VoiceOver) output.
enum CardText {
    /// Compact visual symbol, e.g. "A♠", "10♥".
    static func symbol(_ card: Card) -> String { card.description }

    /// A row of card symbols joined by spaces.
    static func symbols(_ cards: [Card]) -> String {
        cards.map(symbol).joined(separator: " ")
    }

    /// Localized spoken name, e.g. (Italian) "asso di picche".
    static func spoken(_ card: Card) -> String {
        let rank = uiLocalized("card.rank.\(card.rank.rawValue)")
        let suit = uiLocalized("card.suit.\(suitKey(card.suit))")
        return uiLocalized("card.spoken.format", rank, suit)
    }

    /// Localized spoken list of cards, e.g. "asso di picche, re di cuori".
    static func spoken(_ cards: [Card]) -> String {
        cards.map(spoken).joined(separator: ", ")
    }

    static func suitKey(_ suit: Suit) -> String {
        switch suit {
        case .spades: return "spades"
        case .hearts: return "hearts"
        case .diamonds: return "diamonds"
        case .clubs: return "clubs"
        }
    }
}
