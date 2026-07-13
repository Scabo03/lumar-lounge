// OmahaSpeechMap.swift
// =====================================================================
// THE authoritative event → speech-source mapping for Omaha Pot Limit (D-066,
// mirrors the Texas D-029 shape). One pure function decides who speaks each moment:
// the Skypool's own croupier (a vo_it_sky_*.mp3, none produced yet → synthesis
// fallback, D-030), the VoiceOver synthesizer, both, or neither. No event is ever
// spoken by both about the same thing (CONVENTIONS §4).
//
// All croupier voices here are INFORMATIVE — game state the player needs — so each
// falls back to synthesis until its mp3 exists. Bot COLOUR is AMBIENT and lives in
// `OmahaBotChatter`, with a SILENCE fallback (D-066).
//
// The hero's FOUR hole cards are read GROUPED BY SUIT ("asso e re di picche; dieci di
// fiori; …") so a blind player hears the suitedness that drives Omaha value (nut-flush
// potential) without drowning in four flat cards.

import Foundation
import GameWorld
import GameEngine
import Audio

/// The spoken output for one Omaha event: at most a croupier line and a synthesis
/// line, plus a synthesis fallback if the croupier mp3 isn't bundled yet (D-030).
public struct OmahaSpeechPlan: Equatable, Sendable {
    public var croupier: SoundID?
    public var synthesis: OmahaSynthLine?
    public var croupierFallback: OmahaSynthLine?
    public init(croupier: SoundID? = nil, synthesis: OmahaSynthLine? = nil, croupierFallback: OmahaSynthLine? = nil) {
        self.croupier = croupier
        self.synthesis = synthesis
        self.croupierFallback = croupierFallback
    }
    public static let silent = OmahaSpeechPlan()
}

/// A synthesis line for the Omaha table, resolved to concrete data but not localized.
public enum OmahaSynthLine: Equatable, Sendable {
    case heroCards([Card])
    case communityCards([Card])
    /// The street name the croupier would say (its fallback until the mp3 exists).
    case streetName(OmahaStreet)
    case roleSmallBlind
    case roleBigBlind
    case roleButton
    case stakesEscalated(smallBlind: Int, bigBlind: Int)
    case opponentAction(seat: Int, action: OmahaActedAction)
    case shown(who: String, category: HandCategory, bestFive: [Card])
    case heroWon(category: HandCategory?, bestFive: [Card]?)
    case otherWon(who: String, category: HandCategory?, bestFive: [Card]?)
    case splitWon(who: String, category: HandCategory?, bestFive: [Card]?)
    case sessionWon
    case sessionLost
}

public enum OmahaSpeechMap {

    /// PURE: the authoritative spoken plan for one Omaha event.
    public static func plan(for payload: OmahaEventPayload, heroSeatID: Int, names: [Int: String]) -> OmahaSpeechPlan {
        func name(_ id: Int) -> String { names[id] ?? "\(id)" }
        switch payload {

        case .handBegan:
            // A hand-start chime (no essential text) → silent until the mp3 exists.
            return OmahaSpeechPlan(croupier: SoundCatalog.voSkyHandStart)

        case let .stakesEscalated(sb, bb, _):
            return OmahaSpeechPlan(croupier: SoundCatalog.voSkyStakesUp,
                                   croupierFallback: .stakesEscalated(smallBlind: sb, bigBlind: bb))

        case let .privateHoleCards(seatID, cards) where seatID == heroSeatID:
            return OmahaSpeechPlan(synthesis: .heroCards(cards))

        case let .streetOpened(street, cards):
            let croupier: SoundID
            switch street {
            case .flop:  croupier = SoundCatalog.voSkyFlop
            case .turn:  croupier = SoundCatalog.voSkyTurn
            case .river: croupier = SoundCatalog.voSkyRiver
            case .preflop: return .silent
            }
            // Croupier says the street name (or its fallback), then the concrete cards.
            return OmahaSpeechPlan(croupier: croupier, synthesis: .communityCards(cards),
                                   croupierFallback: .streetName(street))

        case let .playerActed(seatID, action):
            let opponent = seatID != heroSeatID
            if isAllIn(action) {
                return OmahaSpeechPlan(croupier: SoundCatalog.voSkyActionAllIn,
                                       synthesis: opponent ? .opponentAction(seat: seatID, action: action) : nil)
            }
            return opponent ? OmahaSpeechPlan(synthesis: .opponentAction(seat: seatID, action: action)) : .silent

        case let .handShown(seatID, _, category, bestFive):
            return OmahaSpeechPlan(croupier: SoundCatalog.voSkyShowdown,
                                   synthesis: .shown(who: name(seatID), category: category, bestFive: bestFive))

        case let .potAwarded(_, _, winnerSeatIDs):
            let split = winnerSeatIDs.count > 1
            let croupier = split ? SoundCatalog.voSkySplitPot : SoundCatalog.voSkyPotAwarded
            let synthesis: OmahaSynthLine = winnerSeatIDs.contains(heroSeatID)
                ? .heroWon(category: nil, bestFive: nil)
                : .otherWon(who: winnerSeatIDs.map(name).joined(separator: ", "), category: nil, bestFive: nil)
            return OmahaSpeechPlan(croupier: croupier, synthesis: synthesis)

        default:
            return .silent
        }
    }

    /// The role announcement at the start of a hand, PERSONAL to the human (D-031):
    /// their own role if they have one, else silence. The Skypool croupier isn't
    /// produced yet, so each declares a synthesis fallback (D-030).
    public static func roleAnnouncement(for payload: OmahaEventPayload, heroSeatID: Int) -> OmahaSpeechPlan {
        guard case let .handBegan(_, _, buttonSeatID, sbSeatID, bbSeatID, _, _, _) = payload else { return .silent }
        if heroSeatID == sbSeatID {
            return OmahaSpeechPlan(croupier: SoundCatalog.voSkyBlindSmall, croupierFallback: .roleSmallBlind)
        }
        if heroSeatID == bbSeatID {
            return OmahaSpeechPlan(croupier: SoundCatalog.voSkyBlindBig, croupierFallback: .roleBigBlind)
        }
        if heroSeatID == buttonSeatID {
            return OmahaSpeechPlan(croupier: SoundCatalog.voSkyRoleButton, croupierFallback: .roleButton)
        }
        return .silent
    }

    static func isAllIn(_ action: OmahaActedAction) -> Bool {
        switch action {
        case .folded, .checked: return false
        case let .called(_, a), let .bet(_, _, a), let .raised(_, _, a): return a
        }
    }

    // MARK: - Rendering

    public static func text(for line: OmahaSynthLine) -> String {
        switch line {
        case let .heroCards(cards):
            return uiLocalized("omaha.announce.hero.cards", omahaHoleSpoken(cards))
        case let .communityCards(cards):
            return CardText.spoken(cards)
        case let .streetName(street):
            switch street {
            case .flop:  return uiLocalized("omaha.announce.street.flop")
            case .turn:  return uiLocalized("omaha.announce.street.turn")
            case .river: return uiLocalized("omaha.announce.street.river")
            case .preflop: return ""
            }
        case .roleSmallBlind:
            return uiLocalized("omaha.announce.role.sb")
        case .roleBigBlind:
            return uiLocalized("omaha.announce.role.bb")
        case .roleButton:
            return uiLocalized("announce.role.button")
        case let .stakesEscalated(sb, bb):
            return uiLocalized("omaha.announce.stakes", sb, bb)
        case let .opponentAction(seat, action):
            return opponentActionText(seat: seat, action: action)
        case let .shown(who, category, bestFive):
            return uiLocalized("announce.shown", who, SpeechMap.handDescription(category: category, bestFive: bestFive))
        case let .heroWon(category, bestFive):
            if let category, let bestFive {
                return uiLocalized("announce.hero.won.category", SpeechMap.handDescription(category: category, bestFive: bestFive))
            }
            return uiLocalized("announce.hero.won")
        case let .otherWon(who, category, bestFive):
            if let category, let bestFive {
                return uiLocalized("announce.other.won.category", who, SpeechMap.handDescription(category: category, bestFive: bestFive))
            }
            return uiLocalized("announce.other.won", who)
        case let .splitWon(who, category, bestFive):
            if let category, let bestFive {
                return uiLocalized("announce.split.won", who, SpeechMap.handDescription(category: category, bestFive: bestFive))
            }
            return uiLocalized("announce.split.won.nohand", who)
        case .sessionWon:
            return uiLocalized("announce.session.won")
        case .sessionLost:
            return uiLocalized("announce.session.lost")
        }
    }

    /// The four hole cards spoken GROUPED BY SUIT (D-066), so suitedness is audible:
    /// suits ordered by count then highest rank, ranks within a suit descending and
    /// joined by the localized "and", each group as "<ranks> di <suit>".
    public static func omahaHoleSpoken(_ cards: [Card]) -> String {
        let join = uiLocalized("omaha.cards.rankjoin")
        let bySuit = Dictionary(grouping: cards, by: { $0.suit })
        let groups = bySuit.sorted { a, b in
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            return (a.value.map { $0.rank.rawValue }.max() ?? 0) > (b.value.map { $0.rank.rawValue }.max() ?? 0)
        }
        return groups.map { suit, suitCards in
            let ranks = suitCards.sorted { $0.rank.rawValue > $1.rank.rawValue }
                .map { uiLocalized("card.rank.\($0.rank.rawValue)") }
                .joined(separator: join)
            let suitName = uiLocalized("card.suit.\(CardText.suitKey(suit))")
            return uiLocalized("card.spoken.format", ranks, suitName)
        }.joined(separator: ", ")
    }

    private static func opponentActionText(seat: Int, action: OmahaActedAction) -> String {
        if isAllIn(action) { return uiLocalized("announce.opp.allin", seat) }
        switch action {
        case .folded:  return uiLocalized("announce.opp.fold", seat)
        case .checked: return uiLocalized("announce.opp.check", seat)
        case .called:  return uiLocalized("announce.opp.call", seat)
        case let .bet(to, _, _):    return uiLocalized("announce.opp.bet", seat, to)
        case let .raised(to, _, _): return uiLocalized("announce.opp.raise", seat, to)
        }
    }

    /// The announcement priority of a synthesis line (D-032).
    public static func priority(for line: OmahaSynthLine) -> AnnouncementPriority {
        switch line {
        case .heroCards, .roleSmallBlind, .roleBigBlind, .roleButton, .stakesEscalated,
             .heroWon, .splitWon, .sessionWon, .sessionLost:
            return .high
        case .otherWon, .opponentAction, .shown, .streetName:
            return .medium
        case .communityCards:
            return .low
        }
    }
}
