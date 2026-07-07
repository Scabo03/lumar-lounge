// AudioScore.swift
// =====================================================================
// The event → sounds mapping (D-023): a PURE function that turns a public
// `SessionEvent` payload into the sound cues to play. It lives in UI — the only
// layer that sees both `SessionEvent` (via GameWorld) and the `Audio` module —
// so the `Audio` module itself stays game-agnostic. Like `TableAnnouncer`
// (event → speech), this is pure and unit-testable, separate from playback.
//
// The croupier voices only the INSTITUTIONAL moments — hand start, blinds,
// flop/turn/river, showdown, pot award — and always plays (D-028). Player actions
// get physical body only (cards, chips) plus the occasional probabilistic bot
// voice, never a croupier line. Hero win/lose/bust and session-final sounds are
// decided by `AudioDirector`, which tracks chip deltas — not here.

import Foundation
import GameWorld
import GameEngine
import Audio

/// One thing to do to the audio engine.
public enum SoundCue: Equatable, Sendable {
    case startAmbient(SoundID)
    case play(SoundID, SoundCategory)
}

/// A bot's spoken lines, chosen by its personality's catalog.
public struct BotVoiceProfile: Equatable, Sendable {
    public let assertive: SoundID   // when betting/raising or winning
    public let letdown: SoundID     // when busting
    public init(assertive: SoundID, letdown: SoundID) {
        self.assertive = assertive
        self.letdown = letdown
    }
}

public enum AudioScore {

    /// The sound cues for one event. Pure: identical inputs (including RNG state)
    /// give identical cues.
    public static func cues(for payload: EventPayload,
                            heroSeatID: Int,
                            voices: [Int: BotVoiceProfile],
                            rng: inout SeededGenerator) -> [SoundCue] {
        switch payload {

        case .sessionBegan:
            return [.startAmbient(SoundCatalog.ambLoungeCalm1)]

        case .handBegan:
            return [.play(SoundCatalog.tblShuffle, .table), .play(SoundCatalog.voHandStart, .croupier)]

        case let .blindPosted(_, blind, _, _):
            let voice = blind == .small ? SoundCatalog.voBlindSmall : SoundCatalog.voBlindBig
            return [.play(SoundCatalog.tblChipsSingle, .table), .play(voice, .croupier)]

        case .holeCardsDealt:
            return [.play(SoundCatalog.tblCardDealSingle, .table)]

        case let .playerActed(seatID, action):
            return actionCues(seatID: seatID, action: action, heroSeatID: heroSeatID, voices: voices, rng: &rng)

        case let .streetOpened(street, _):
            switch street {
            case .flop:  return [.play(SoundCatalog.tblCardsDealFlop, .table), .play(SoundCatalog.voFlop, .croupier)]
            case .turn:  return [.play(SoundCatalog.tblCardFlipSingle, .table), .play(SoundCatalog.voTurn, .croupier)]
            case .river: return [.play(SoundCatalog.tblCardFlipSingle, .table), .play(SoundCatalog.voRiver, .croupier)]
            case .preflop: return []
            }

        case .handShown:
            // Cards turned face-up at showdown (one flip per shown seat).
            return [.play(SoundCatalog.tblCardFlipSingle, .table)]

        case let .potAwarded(_, _, winnerSeatIDs):
            var cues: [SoundCue] = [.play(SoundCatalog.tblChipsPotCollect, .table)]
            cues.append(.play(winnerSeatIDs.count > 1 ? SoundCatalog.voSplitPot : SoundCatalog.voPotAwarded, .croupier))
            if let botWinner = winnerSeatIDs.first(where: { voices[$0] != nil }),
               let profile = voices[botWinner], botWinner != heroSeatID, roll(&rng) < 0.4 {
                cues.append(.play(profile.assertive, .botVoice))
            }
            return cues

        case let .playerBusted(playerID):
            if playerID == heroSeatID { return [.play(SoundCatalog.fxBustHero, .effect)] }
            var cues: [SoundCue] = [.play(SoundCatalog.fxBustPlayer, .effect)]
            if let profile = voices[playerID], roll(&rng) < 0.6 {
                cues.append(.play(profile.letdown, .botVoice))
            }
            return cues

        // Handled by the director (chip-delta based) or intentionally silent:
        case .handEnded, .sessionEnded, .privateHoleCards, .playerJoined, .playerLeft:
            return []
        }
    }

    /// Player actions get only PHYSICAL sounds (chips, muck) and, occasionally, a
    /// bot's own voice — never the croupier's institutional voice and never a
    /// VoiceOver line (D-028, strategy C): the table noise and the optional bot
    /// voice are enough to suggest a bot acted, without a repetitive announcement.
    private static func actionCues(seatID: Int, action: ActedAction,
                                   heroSeatID: Int, voices: [Int: BotVoiceProfile],
                                   rng: inout SeededGenerator) -> [SoundCue] {
        switch action {
        case .folded:
            return [.play(SoundCatalog.tblMuck, .table)]
        case .checked:
            return []
        case let .called(_, isAllIn):
            return isAllIn ? allInCues() : [.play(SoundCatalog.tblChipsStack, .table)]
        case let .bet(_, _, isAllIn), let .raised(_, _, isAllIn):
            var cues: [SoundCue] = isAllIn ? allInCues() : [.play(SoundCatalog.tblChipsStack, .table)]
            // An aggressive bot occasionally talks it up.
            if let profile = voices[seatID], seatID != heroSeatID, roll(&rng) < 0.35 {
                cues.append(.play(profile.assertive, .botVoice))
            }
            return cues
        }
    }

    /// Any all-in: big chips and the dramatic sting (a non-spoken effect). No
    /// croupier voice — the drama is the effect, not an announcement (D-028).
    private static func allInCues() -> [SoundCue] {
        [.play(SoundCatalog.tblChipsBetLarge, .table),
         .play(SoundCatalog.fxAllInDramatic, .effect)]
    }

    /// A uniform Double in [0, 1) from the seeded generator.
    private static func roll(_ rng: inout SeededGenerator) -> Double {
        Double(rng.next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
