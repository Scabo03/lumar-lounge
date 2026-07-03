// TableAnnouncer.swift
// =====================================================================
// Turns session events into VoiceOver narration. Split in two so the semantic
// decision is testable without localization (D-016):
//   1. `spoken(for:names:)` — PURE: maps an event to a `SpokenEvent` (or nil if
//      the moment needs no narration). Fully unit-testable.
//   2. `text(for:)` — renders a `SpokenEvent` into a localized, Italian-phonetic
//      string via the localization tables.
//
// The non-vedente must never lose information relative to the vedente ("nessuno
// perde niente"): every visible change that matters has a spoken counterpart.

import Foundation
import GameWorld
import GameEngine

/// A narratable moment, with the concrete data already resolved to names.
public enum SpokenEvent: Equatable, Sendable {
    case sessionStart
    case handStart(handNumber: Int, buttonName: String)
    case blind(kind: BlindKind, who: String, amount: Int)
    case dealtHoleCards
    case acted(who: String, action: ActedAction)
    case street(Street, cards: [Card])
    case shown(who: String, cards: [Card], category: HandCategory)
    case potAwarded(amount: Int, winners: [String])
    case handEnd(winner: String?, chips: Int?)
    case bust(who: String)
    case winner(who: String)
}

public enum TableAnnouncer {

    /// PURE: maps an event to what should be spoken, resolving ids to names.
    /// Returns nil for events that need no narration on their own.
    public static func spoken(for payload: EventPayload, names: [Int: String]) -> SpokenEvent? {
        func name(_ id: Int) -> String { names[id] ?? "\(id)" }
        switch payload {
        case .sessionBegan:
            return .sessionStart
        case let .handBegan(handNumber, _, buttonSeatID, _, _, _, _, _):
            return .handStart(handNumber: handNumber + 1, buttonName: name(buttonSeatID))
        case let .blindPosted(seatID, kind, amount, _):
            return .blind(kind: kind, who: name(seatID), amount: amount)
        case let .playerActed(seatID, action):
            return .acted(who: name(seatID), action: action)
        case let .streetOpened(street, cards):
            return .street(street, cards: cards)
        case let .handShown(seatID, holeCards, category, _):
            return .shown(who: name(seatID), cards: holeCards, category: category)
        case let .potAwarded(_, amount, winnerSeatIDs):
            return .potAwarded(amount: amount, winners: winnerSeatIDs.map(name))
        case let .playerBusted(playerID):
            return .bust(who: name(playerID))
        case let .sessionEnded(reason):
            // The concrete winner name is filled in by the caller if known.
            _ = reason
            return nil
        // Deliberately silent on their own (covered by neighbouring events):
        case .holeCardsDealt, .privateHoleCards, .handEnded, .playerJoined, .playerLeft:
            return nil
        }
    }

    /// Renders a spoken moment into a localized, phonetic string.
    public static func text(for spoken: SpokenEvent) -> String {
        switch spoken {
        case .sessionStart:
            return uiLocalized("announce.session.start")
        case let .handStart(handNumber, buttonName):
            return uiLocalized("announce.hand.start", handNumber, buttonName)
        case let .blind(kind, who, amount):
            let key = kind == .small ? "announce.blind.small" : "announce.blind.big"
            return uiLocalized(key, who, amount)
        case .dealtHoleCards:
            return uiLocalized("announce.hole.dealt")
        case let .acted(who, action):
            return actionText(who: who, action: action)
        case let .street(street, cards):
            return uiLocalized(streetKey(street), CardText.spoken(cards))
        case let .shown(who, cards, category):
            return uiLocalized("announce.shown", who, CardText.spoken(cards), categoryText(category))
        case let .potAwarded(amount, winners):
            return uiLocalized("announce.pot.awarded", winners.joined(separator: ", "), amount)
        case let .handEnd(winner, chips):
            if let winner, let chips {
                return uiLocalized("announce.hand.end.winner", winner, chips)
            }
            return uiLocalized("announce.hand.end")
        case let .bust(who):
            return uiLocalized("announce.bust", who)
        case let .winner(who):
            return uiLocalized("announce.session.winner", who)
        }
    }

    // MARK: - Fragments

    private static func actionText(who: String, action: ActedAction) -> String {
        switch action {
        case .folded:
            return uiLocalized("announce.action.folded", who)
        case .checked:
            return uiLocalized("announce.action.checked", who)
        case let .called(amount, isAllIn):
            return uiLocalized(isAllIn ? "announce.action.called.allin" : "announce.action.called", who, amount)
        case let .bet(to, _, isAllIn):
            return uiLocalized(isAllIn ? "announce.action.bet.allin" : "announce.action.bet", who, to)
        case let .raised(to, _, isAllIn):
            return uiLocalized(isAllIn ? "announce.action.raised.allin" : "announce.action.raised", who, to)
        }
    }

    private static func streetKey(_ street: Street) -> String {
        switch street {
        case .preflop: return "announce.street.flop" // preflop has no reveal; not used
        case .flop: return "announce.street.flop"
        case .turn: return "announce.street.turn"
        case .river: return "announce.street.river"
        }
    }

    static func categoryText(_ category: HandCategory) -> String {
        uiLocalized("hand.category.\(category.rawValue)")
    }
}
