// DrawSpeechMap.swift
// =====================================================================
// THE authoritative event → speech-source mapping for Five-Card Draw (D-044,
// extends D-029). One pure function decides who speaks each moment: the croupier
// (a vo_it_*.mp3, several of them not produced yet → synthesis fallback, D-030),
// the VoiceOver synthesizer, both, or neither. No event is ever spoken by both
// about the same thing (CONVENTIONS §4).
//
// Distinct from the Texas `SpeechMap` (different events), but it reuses the same
// two-layer, testable shape and the shared croupier voices where they still fit
// (your-turn, all-in, showdown, pot). The rendering (`text`) uses draw.* strings.

import Foundation
import GameWorld
import GameEngine
import Audio

/// The spoken output for one draw event: at most a croupier line and a synthesis
/// line, plus a synthesis fallback if the croupier mp3 isn't bundled yet (D-030).
public struct DrawSpeechPlan: Equatable, Sendable {
    public var croupier: SoundID?
    public var synthesis: DrawSynthLine?
    public var croupierFallback: DrawSynthLine?
    public init(croupier: SoundID? = nil, synthesis: DrawSynthLine? = nil, croupierFallback: DrawSynthLine? = nil) {
        self.croupier = croupier
        self.synthesis = synthesis
        self.croupierFallback = croupierFallback
    }
    public static let silent = DrawSpeechPlan()
}

/// A synthesis line for the draw table, resolved to concrete data but not yet
/// localized. Only content the croupier cannot pre-record appears as data.
public enum DrawSynthLine: Equatable, Sendable {
    case ante
    case carriedPot(Int)
    case heroCards([Card])
    case heroDrewCards([Card])
    case opponentAction(seat: Int, action: DrawActedAction)
    case opponentDrew(seat: Int, count: Int)
    case yourTurnContext(toCall: Int, pot: Int)
    case drawPhase
    case passedIn
    /// A seat's revealed hand at showdown — spoken as its COMBINATION plus a
    /// relevant kicker, never card-by-card (D-045).
    case shown(who: String, category: HandCategory, bestFive: [Card])
    case openersDisqualified(seat: Int)
    case heroWon(category: HandCategory?, bestFive: [Card]?)
    case otherWon(who: String, category: HandCategory?, bestFive: [Card]?)
    case splitWon(who: String, category: HandCategory?, bestFive: [Card]?)
    case sessionWon
    case sessionLost
}

public enum DrawSpeechMap {

    /// PURE: the authoritative spoken plan for one draw event.
    public static func plan(for payload: DrawEventPayload, heroSeatID: Int, names: [Int: String]) -> DrawSpeechPlan {
        func name(_ id: Int) -> String { names[id] ?? "\(id)" }
        switch payload {

        case .handBegan:
            // The croupier calls the ante round (mp3 not produced → synthesis).
            return DrawSpeechPlan(croupier: SoundCatalog.voAnte, croupierFallback: .ante)

        case let .privateCards(seatID, cards) where seatID == heroSeatID:
            return DrawSpeechPlan(synthesis: .heroCards(cards))

        case let .playerActed(seatID, action, _):
            let opponent = seatID != heroSeatID
            if isAllIn(action) {
                return DrawSpeechPlan(croupier: SoundCatalog.voActionAllIn,
                                      synthesis: opponent ? .opponentAction(seat: seatID, action: action) : nil)
            }
            return opponent ? DrawSpeechPlan(synthesis: .opponentAction(seat: seatID, action: action)) : .silent

        case .passedIn:
            return DrawSpeechPlan(croupier: SoundCatalog.voPassAndOut, croupierFallback: .passedIn)

        case .drawPhaseBegan:
            return DrawSpeechPlan(croupier: SoundCatalog.voDrawPhase, croupierFallback: .drawPhase)

        case let .playerDrew(seatID, count) where seatID != heroSeatID:
            return DrawSpeechPlan(synthesis: .opponentDrew(seat: seatID, count: count))

        case let .privateDrawnCards(seatID, cards) where seatID == heroSeatID:
            return DrawSpeechPlan(synthesis: .heroDrewCards(cards))

        case let .handShown(seatID, _, category, bestFive):
            return DrawSpeechPlan(croupier: SoundCatalog.voShowdown,
                                  synthesis: .shown(who: name(seatID), category: category, bestFive: bestFive))

        case let .openersDisqualified(seatID):
            return DrawSpeechPlan(croupier: SoundCatalog.voOpenersDisqualified,
                                  synthesis: .openersDisqualified(seat: seatID),
                                  croupierFallback: .openersDisqualified(seat: seatID))

        case let .potAwarded(_, _, winnerSeatIDs):
            let split = winnerSeatIDs.count > 1
            let croupier = split ? SoundCatalog.voSplitPot : SoundCatalog.voPotAwarded
            let synthesis: DrawSynthLine = winnerSeatIDs.contains(heroSeatID)
                ? .heroWon(category: nil, bestFive: nil)
                : .otherWon(who: winnerSeatIDs.map(name).joined(separator: ", "), category: nil, bestFive: nil)
            return DrawSpeechPlan(croupier: croupier, synthesis: synthesis)

        default:
            // session lifecycle, antePosted, cardsDealt (public), potOpened,
            // secondBetBegan, hero's own action/draw, busts, joins/leaves → silent.
            return .silent
        }
    }

    static func isAllIn(_ action: DrawActedAction) -> Bool {
        switch action {
        case .folded, .checked: return false
        case let .called(_, a), let .bet(_, a), let .raised(_, a): return a
        }
    }

    // MARK: - Rendering

    public static func text(for line: DrawSynthLine) -> String {
        switch line {
        case .ante:
            return uiLocalized("draw.announce.ante")
        case let .carriedPot(amount):
            return uiLocalized("draw.announce.carried", amount)
        case let .heroCards(cards):
            return uiLocalized("draw.announce.hero.cards", CardText.spoken(cards))
        case let .heroDrewCards(cards):
            return uiLocalized("draw.announce.hero.drew", CardText.spoken(cards))
        case let .opponentAction(seat, action):
            return opponentActionText(seat: seat, action: action)
        case let .opponentDrew(seat, count):
            return count == 0
                ? uiLocalized("draw.announce.opp.standpat", seat)
                : uiLocalized("draw.announce.opp.drew", seat, count)
        case let .yourTurnContext(toCall, pot):
            return uiLocalized("announce.your.turn.context", toCall, pot)
        case .drawPhase:
            return uiLocalized("draw.announce.drawphase")
        case .passedIn:
            return uiLocalized("draw.announce.passedin")
        case let .shown(who, category, bestFive):
            return uiLocalized("announce.shown", who, SpeechMap.handDescription(category: category, bestFive: bestFive))
        case let .openersDisqualified(seat):
            return uiLocalized("draw.announce.disqualified", seat)
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

    private static func opponentActionText(seat: Int, action: DrawActedAction) -> String {
        if isAllIn(action) { return uiLocalized("announce.opp.allin", seat) }
        switch action {
        case .folded:  return uiLocalized("announce.opp.fold", seat)
        case .checked: return uiLocalized("announce.opp.check", seat)
        case .called:  return uiLocalized("announce.opp.call", seat)
        case let .bet(amount, _):    return uiLocalized("draw.announce.opp.bet", seat, amount)
        case let .raised(amount, _): return uiLocalized("draw.announce.opp.raise", seat, amount)
        }
    }

    /// The announcement priority of a synthesis line (D-032).
    public static func priority(for line: DrawSynthLine) -> AnnouncementPriority {
        switch line {
        case .heroCards, .heroDrewCards, .yourTurnContext, .heroWon, .splitWon, .sessionWon, .sessionLost,
             .openersDisqualified, .passedIn, .carriedPot:
            return .high
        case .otherWon, .opponentAction, .opponentDrew, .shown, .ante, .drawPhase:
            return .medium
        }
    }
}
