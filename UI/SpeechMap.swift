// SpeechMap.swift
// =====================================================================
// THE authoritative event → speech-source mapping (D-029). One pure function is
// the single source of truth for who speaks each moment: the pre-recorded
// croupier (a vo_it_*.mp3), the VoiceOver synthesizer (localized text), both (the
// croupier first, then synthesis for content that can't be pre-recorded, like the
// concrete flop cards), or neither.
//
// Two layers, testable without localization (as in M1.6):
//   1. `plan(for:heroSeatID:names:)` — PURE: event → `SpeechPlan` (a croupier
//      SoundID and/or a resolved `SynthLine`). This IS the table.
//   2. `text(for:)` — renders a `SynthLine` into a localized, Italian-phonetic
//      string.
//
// Physical table sounds, effects, ambient and bot voices are NOT here — they are
// the non-spoken layer owned by `AudioScore`/`AudioDirector`. This file governs
// only the two SPEAKING systems, so no event is ever spoken by both croupier and
// synthesis about the same thing (see CONVENTIONS §4, D-029).

import Foundation
import GameWorld
import GameEngine
import Audio

/// The spoken output for one event: at most a croupier line and a synthesis line.
/// When both are present the croupier plays first and the synthesis follows at
/// the end of the mp3 (the conductor enforces the order).
public struct SpeechPlan: Equatable, Sendable {
    public var croupier: SoundID?
    public var synthesis: SynthLine?
    /// The synthesis to speak IF `croupier`'s file is missing from the bundle
    /// (mp3→speech fallback, D-030). Ignored once the mp3 is present.
    public var croupierFallback: SynthLine?
    public init(croupier: SoundID? = nil, synthesis: SynthLine? = nil, croupierFallback: SynthLine? = nil) {
        self.croupier = croupier
        self.synthesis = synthesis
        self.croupierFallback = croupierFallback
    }
    public static let silent = SpeechPlan()
}

/// A synthesis line, resolved to concrete data (names/cards) but not yet
/// localized. Only content the croupier cannot pre-record appears here.
public enum SynthLine: Equatable, Sendable {
    /// The human's own two hole cards.
    case heroCards([Card])
    /// The concrete community cards just revealed (flop = 3, turn/river = 1).
    case communityCards([Card])
    /// Context added after "it's your turn", only when there is something to call.
    case yourTurnContext(toCall: Int, pot: Int)
    /// A seat's revealed hand at showdown.
    case shown(who: String, cards: [Card], category: HandCategory)
    /// The human won the pot (with the hand category if it went to showdown).
    case heroWon(category: HandCategory?)
    /// Someone else won the pot.
    case otherWon(who: String, category: HandCategory?)
    case sessionWon
    case sessionLost
    /// An opponent's action, attributed by their on-screen seat number (D-031).
    case opponentAction(seat: Int, action: ActedAction)
    /// Fallback for the (not-yet-produced) button-role mp3: "sei sul bàtton".
    case roleButton
}

public enum SpeechMap {

    /// PURE: the authoritative spoken plan for one event. Cross-event detail that
    /// a single event can't carry (e.g. the winner's hand category at pot time) is
    /// left `nil` here and enriched by the stateful consumer before rendering.
    public static func plan(for payload: EventPayload, heroSeatID: Int, names: [Int: String]) -> SpeechPlan {
        func name(_ id: Int) -> String { names[id] ?? "\(id)" }
        switch payload {

        case .handBegan:
            // The generic small/big-blind announcements are gone (D-031); the
            // human's role is announced separately via `roleAnnouncement`.
            return SpeechPlan(croupier: SoundCatalog.voHandStart)

        case let .privateHoleCards(seatID, cards) where seatID == heroSeatID:
            return SpeechPlan(synthesis: .heroCards(cards))

        case let .streetOpened(street, cards):
            switch street {
            case .flop:  return SpeechPlan(croupier: SoundCatalog.voFlop,  synthesis: .communityCards(cards))
            case .turn:  return SpeechPlan(croupier: SoundCatalog.voTurn,  synthesis: .communityCards(cards))
            case .river: return SpeechPlan(croupier: SoundCatalog.voRiver, synthesis: .communityCards(cards))
            case .preflop: return .silent
            }

        case let .playerActed(seatID, action):
            let opponent = seatID != heroSeatID
            if isAllIn(action) {
                // The croupier calls the all-in; opponents also get an attribution
                // synthesis after it (D-031). The hero's own all-in is croupier-only.
                return SpeechPlan(croupier: SoundCatalog.voActionAllIn,
                                  synthesis: opponent ? .opponentAction(seat: seatID, action: action) : nil)
            }
            // Opponents' ordinary actions fill the acoustic gap with a synthesis
            // (D-031); the human's own action stays silent (physical sounds only).
            return opponent ? SpeechPlan(synthesis: .opponentAction(seat: seatID, action: action)) : .silent

        case let .handShown(seatID, cards, category, _):
            // voShowdown is a once-per-hand cue: the conductor de-dupes it across
            // the several handShown events; each still reads its own hand.
            return SpeechPlan(croupier: SoundCatalog.voShowdown,
                              synthesis: .shown(who: name(seatID), cards: cards, category: category))

        case let .potAwarded(_, _, winnerSeatIDs):
            // The croupier voice is once-per-hand (the conductor de-dupes across
            // main + side pots — the "broken record" fix). Category is nil here and
            // filled in by the consumer from the tracked showdown, if any.
            let split = winnerSeatIDs.count > 1
            let croupier = split ? SoundCatalog.voSplitPot : SoundCatalog.voPotAwarded
            let synthesis: SynthLine = winnerSeatIDs.contains(heroSeatID)
                ? .heroWon(category: nil)
                : .otherWon(who: winnerSeatIDs.map(name).joined(separator: ", "), category: nil)
            return SpeechPlan(croupier: croupier, synthesis: synthesis)

        default:
            // Session start/end, hole-cards-dealt (public), opponents' non-all-in
            // actions, hero's own action, busts, joins/leaves → no spoken layer.
            return .silent
        }
    }

    /// The role announcement at the start of a hand, PERSONAL to the human (D-031):
    /// their own role if they have one (small blind / big blind / button), else
    /// silence — never the generic "small blind, big blind" of before. The button
    /// mp3 isn't produced yet, so it declares a synthesis fallback (D-030).
    public static func roleAnnouncement(for payload: EventPayload, heroSeatID: Int) -> SpeechPlan {
        guard case let .handBegan(_, _, buttonSeatID, sbSeatID, bbSeatID, _, _, _) = payload else { return .silent }
        if heroSeatID == sbSeatID { return SpeechPlan(croupier: SoundCatalog.voBlindSmall) }
        if heroSeatID == bbSeatID { return SpeechPlan(croupier: SoundCatalog.voBlindBig) }
        if heroSeatID == buttonSeatID {
            return SpeechPlan(croupier: SoundCatalog.voRoleButton, croupierFallback: .roleButton)
        }
        return .silent
    }

    /// True for any all-in action (call/bet/raise that put the seat all-in).
    static func isAllIn(_ action: ActedAction) -> Bool {
        switch action {
        case .folded, .checked: return false
        case let .called(_, a), let .bet(_, _, a), let .raised(_, _, a): return a
        }
    }

    // MARK: - Rendering

    /// Renders a synthesis line into a localized, Italian-phonetic string.
    public static func text(for line: SynthLine) -> String {
        switch line {
        case let .heroCards(cards):
            return uiLocalized("announce.hero.cards", CardText.spoken(cards))
        case let .communityCards(cards):
            // Just the concrete cards; the croupier already said "flop"/"turn"/etc.
            return CardText.spoken(cards)
        case let .yourTurnContext(toCall, pot):
            return uiLocalized("announce.your.turn.context", toCall, pot)
        case let .shown(who, cards, category):
            return uiLocalized("announce.shown", who, CardText.spoken(cards), categoryText(category))
        case let .heroWon(category):
            if let category { return uiLocalized("announce.hero.won.category", categoryText(category)) }
            return uiLocalized("announce.hero.won")
        case let .otherWon(who, category):
            if let category { return uiLocalized("announce.other.won.category", who, categoryText(category)) }
            return uiLocalized("announce.other.won", who)
        case .sessionWon:
            return uiLocalized("announce.session.won")
        case .sessionLost:
            return uiLocalized("announce.session.lost")
        case let .opponentAction(seat, action):
            return opponentActionText(seat: seat, action: action)
        case .roleButton:
            return uiLocalized("announce.role.button")
        }
    }

    /// "giocatore N …" attributed by the on-screen seat number (D-031). Poker
    /// verbs stay Italian where natural (passa/chiama/rilancia); fold/all-in are
    /// rendered phonetically (foulda / ol-in).
    private static func opponentActionText(seat: Int, action: ActedAction) -> String {
        if isAllIn(action) { return uiLocalized("announce.opp.allin", seat) }
        switch action {
        case .folded:  return uiLocalized("announce.opp.fold", seat)
        case .checked: return uiLocalized("announce.opp.check", seat)
        case .called:  return uiLocalized("announce.opp.call", seat)
        case let .bet(to, _, _), let .raised(to, _, _): return uiLocalized("announce.opp.raise", seat, to)
        }
    }

    static func categoryText(_ category: HandCategory) -> String {
        uiLocalized("hand.category.\(category.rawValue)")
    }

    /// The announcement priority of a synthesis line (D-032): personal/critical =
    /// high (never dropped); opponent info = medium; secondary description = low.
    public static func priority(for line: SynthLine) -> AnnouncementPriority {
        switch line {
        case .heroCards, .yourTurnContext, .heroWon, .sessionWon, .sessionLost, .roleButton:
            return .high
        case .otherWon, .opponentAction, .shown:
            return .medium
        case .communityCards:
            return .low
        }
    }
}
