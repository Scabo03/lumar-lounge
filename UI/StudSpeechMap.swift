// StudSpeechMap.swift
// =====================================================================
// THE authoritative event → speech-source mapping for the ClockTower's Seven-Card Stud
// (D-077, mirrors the Machiavelli/Omaha shape). One pure function decides who speaks each
// moment: the ClockTower custode (the old man, a vo_it_clock_poker_*.mp3, none produced
// yet → synthesis fallback, D-030), the VoiceOver synthesizer, both, or neither. No event
// is ever spoken by both about the same thing (CONVENTIONS §4).
//
// The croupier's register is erudite Italian, no anglicisms in the spoken line
// ("rilancio", not "raise") — the pulsanti stay Raise/Fold/Call (D-073, not uniformed).
//
// THE ACCESSIBILITY HEART (D-078): Stud has no community board — every player has DIFFERENT
// up cards, and reading them is the game. So the map ANNOUNCES each up card as it is dealt
// (parity with the sighted player who SEES it appear), attributed by name; the on-demand
// FULL recall of each opponent's board lives on the opponent badge in the view. It DESCRIBES
// the public cards, never ADVISES ("il Professore riceve il re" — not "attento al colore").

import Foundation
import GameWorld
import GameEngine
import Audio

/// The spoken output for one Stud event: at most a croupier line and a synthesis line,
/// plus a synthesis fallback if the croupier mp3 isn't bundled yet (D-030).
public struct StudSpeechPlan: Equatable, Sendable {
    public var croupier: SoundID?
    public var synthesis: StudSynthLine?
    public var croupierFallback: StudSynthLine?
    public init(croupier: SoundID? = nil, synthesis: StudSynthLine? = nil, croupierFallback: StudSynthLine? = nil) {
        self.croupier = croupier
        self.synthesis = synthesis
        self.croupierFallback = croupierFallback
    }
    public static let silent = StudSpeechPlan()
}

/// A synthesis line for the Stud table, resolved to concrete data but not localized.
public enum StudSynthLine: Equatable, Sendable {
    case heroDownCards([Card])
    /// An up card dealt to a seat (attributed by name; `isHero` picks the "you" phrasing).
    case upCard(who: String, card: Card, isHero: Bool)
    case bringIn(who: String, amount: Int)
    case streetName(StudStreet)
    case opponentAction(who: String, action: StudActedAction)
    case shown(who: String, category: HandCategory, bestFive: [Card])
    case heroWon(category: HandCategory?, bestFive: [Card]?)
    case otherWon(who: String, category: HandCategory?, bestFive: [Card]?)
    case splitWon(who: String, category: HandCategory?, bestFive: [Card]?)
    case housePrize(amount: Int)
    case sessionWon
    case sessionLost
}

public enum StudSpeechMap {

    /// PURE: the authoritative spoken plan for one Stud event.
    public static func plan(for payload: StudEventPayload, heroSeatID: Int, names: [Int: String]) -> StudSpeechPlan {
        func name(_ id: Int) -> String { names[id] ?? "\(id)" }
        switch payload {

        case .handBegan:
            return StudSpeechPlan(croupier: SoundCatalog.voClockPokerHandStart,
                                  croupierFallback: .streetName(.third))   // "Nuova mano." handled in text

        case let .privateDownCards(seatID, cards) where seatID == heroSeatID:
            return StudSpeechPlan(synthesis: .heroDownCards(cards))

        case let .upCardDealt(seatID, card, _):
            return StudSpeechPlan(synthesis: .upCard(who: name(seatID), card: card, isHero: seatID == heroSeatID))

        case let .bringInPosted(seatID, amount, _):
            return StudSpeechPlan(synthesis: .bringIn(who: name(seatID), amount: amount))

        case let .streetBegan(street):
            let croupier: SoundID
            switch street {
            case .fourth:  croupier = SoundCatalog.voClockPokerStreet4
            case .fifth:   croupier = SoundCatalog.voClockPokerStreet5
            case .sixth:   croupier = SoundCatalog.voClockPokerStreet6
            case .seventh: croupier = SoundCatalog.voClockPokerStreet7
            case .third:   return .silent
            }
            return StudSpeechPlan(croupier: croupier, croupierFallback: .streetName(street))

        case let .playerActed(seatID, action):
            let opponent = seatID != heroSeatID
            if isAllIn(action) {
                return StudSpeechPlan(croupier: SoundCatalog.voClockPokerAllIn,
                                      synthesis: opponent ? .opponentAction(who: name(seatID), action: action) : nil)
            }
            return opponent ? StudSpeechPlan(synthesis: .opponentAction(who: name(seatID), action: action)) : .silent

        case let .handShown(seatID, _, category, bestFive):
            return StudSpeechPlan(croupier: SoundCatalog.voClockPokerShowdown,
                                  synthesis: .shown(who: name(seatID), category: category, bestFive: bestFive))

        case let .potAwarded(_, _, winnerSeatIDs):
            let synthesis: StudSynthLine = winnerSeatIDs.contains(heroSeatID)
                ? .heroWon(category: nil, bestFive: nil)
                : .otherWon(who: winnerSeatIDs.map(name).joined(separator: ", "), category: nil, bestFive: nil)
            return StudSpeechPlan(croupier: SoundCatalog.voClockPokerPot, synthesis: synthesis)

        case let .housePrizeAwarded(_, amount):
            return StudSpeechPlan(croupier: SoundCatalog.voClockPokerHousePrize, synthesis: .housePrize(amount: amount))

        default:
            return .silent
        }
    }

    static func isAllIn(_ action: StudActedAction) -> Bool {
        switch action {
        case .folded, .checked: return false
        case let .called(_, a), let .bet(_, _, a), let .raised(_, _, a): return a
        }
    }

    // MARK: - Rendering

    public static func text(for line: StudSynthLine) -> String {
        switch line {
        case let .heroDownCards(cards):
            let key = cards.count == 1 ? "stud.announce.hero.down.one" : "stud.announce.hero.down"
            return uiLocalized(key, CardText.spoken(cards))
        case let .upCard(who, card, isHero):
            return isHero
                ? uiLocalized("stud.announce.upcard.hero", CardText.spoken(card))
                : uiLocalized("stud.announce.upcard", who, CardText.spoken(card))
        case let .bringIn(who, amount):
            return uiLocalized("stud.announce.bringin", who, amount)
        case let .streetName(street):
            switch street {
            case .third:   return uiLocalized("stud.announce.handstart")
            case .fourth:  return uiLocalized("stud.announce.street.4")
            case .fifth:   return uiLocalized("stud.announce.street.5")
            case .sixth:   return uiLocalized("stud.announce.street.6")
            case .seventh: return uiLocalized("stud.announce.street.7")
            }
        case let .opponentAction(who, action):
            return opponentActionText(who: who, action: action)
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
        case let .housePrize(amount):
            return uiLocalized("stud.announce.houseprize", amount)
        case .sessionWon:
            return uiLocalized("announce.session.won")
        case .sessionLost:
            return uiLocalized("announce.session.lost")
        }
    }

    private static func opponentActionText(who: String, action: StudActedAction) -> String {
        if isAllIn(action) { return uiLocalized("stud.announce.action.allin", who) }
        switch action {
        case .folded:  return uiLocalized("stud.announce.action.fold", who)
        case .checked: return uiLocalized("stud.announce.action.check", who)
        case .called:  return uiLocalized("stud.announce.action.call", who)
        case let .bet(to, _, _):    return uiLocalized("stud.announce.action.bet", who, to)
        case let .raised(to, _, _): return uiLocalized("stud.announce.action.raise", who, to)
        }
    }

    /// The announcement priority of a synthesis line (D-032). The hero's PERSONAL lines
    /// (own cards, own win, prize) are high; opponents' cards/actions medium; nothing low.
    public static func priority(for line: StudSynthLine) -> AnnouncementPriority {
        switch line {
        case .heroDownCards, .heroWon, .splitWon, .housePrize, .sessionWon, .sessionLost:
            return .high
        case .upCard, .bringIn, .opponentAction, .shown, .otherWon, .streetName:
            return .medium
        }
    }
}
