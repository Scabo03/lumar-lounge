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
    /// The hero's own cards as ONE whole. On third street that is all THREE — the
    /// two down and the up — because a hand the sighted player takes in at a glance
    /// must not reach the blind player as two sentences, one of which calls itself
    /// "your cards" while listing two of three (D-094, finishing what D-089 began).
    case heroCards([Card])
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
            // The custode's "new hand" flourish (mp3 delivered). No register fallback — if
            // it were ever missing it stays silent (the ClockTower's lower verbosity, D-080).
            return StudSpeechPlan(croupier: SoundCatalog.voTowerNewHand)

        case let .privateDownCards(seatID, cards) where seatID == heroSeatID:
            return StudSpeechPlan(synthesis: .heroCards(cards))

        case let .upCardDealt(seatID, card, _):
            return StudSpeechPlan(synthesis: .upCard(who: name(seatID), card: card, isHero: seatID == heroSeatID))

        case let .bringInPosted(seatID, amount, _):
            return StudSpeechPlan(synthesis: .bringIn(who: name(seatID), amount: amount))

        case .streetBegan:
            // The Stud street cues were NOT produced (the delivered set is Texas-flavoured:
            // flop/turn/river), so per the ClockTower's lower verbosity they are SILENT
            // (D-080). The street's CONTENT — each new up card — is still announced as it is
            // dealt (the `upCardDealt` synthesis above), so no information is lost.
            return .silent

        case let .playerActed(seatID, action):
            // No all-in croupier cue was delivered → silent register; the opponent action
            // CONTENT ("il Professore punta tutto") still speaks (accessibility, D-080).
            let opponent = seatID != heroSeatID
            return opponent ? StudSpeechPlan(synthesis: .opponentAction(who: name(seatID), action: action)) : .silent

        case let .handShown(seatID, _, category, bestFive):
            return StudSpeechPlan(croupier: SoundCatalog.voTowerShowdown,
                                  synthesis: .shown(who: name(seatID), category: category, bestFive: bestFive))

        case let .potAwarded(_, _, winnerSeatIDs):
            let split = winnerSeatIDs.count > 1
            let synthesis: StudSynthLine = winnerSeatIDs.contains(heroSeatID)
                ? .heroWon(category: nil, bestFive: nil)
                : .otherWon(who: winnerSeatIDs.map(name).joined(separator: ", "), category: nil, bestFive: nil)
            return StudSpeechPlan(croupier: split ? SoundCatalog.voTowerSplitPot : SoundCatalog.voTowerPotAwarded,
                                  synthesis: synthesis)

        // The House-Prize line (`.housePrize`) is not an event plan (D-079): the prize is
        // paid at cash-out, and the view model narrates it directly at the win.

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
        case let .heroCards(cards):
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
        case .heroCards, .heroWon, .splitWon, .housePrize, .sessionWon, .sessionLost:
            return .high
        case .upCard, .bringIn, .shown, .otherWon, .streetName:
            return .medium
        case .opponentAction:
            // LOW, and deliberately below the up cards (D-094). Both used to be
            // medium, so a saturated channel evicted them alike — and since the
            // chatter is both more numerous and longer (measured: 7.00 lines and
            // 15.96 s per hand against 5.82 and 11.06), it was crowding out the
            // one thing Seven-Card Stud is actually played on. An opponent's call
            // is routine, on screen, and re-derivable from the pot; the card that
            // just landed in front of them is not. No line was added and no budget
            // was raised: only the order in which the channel gives way.
            return .low
        }
    }
}
