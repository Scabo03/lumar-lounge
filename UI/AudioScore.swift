// AudioScore.swift
// =====================================================================
// The NON-spoken layer of the event → sound mapping (D-029): physical table
// sounds (cards, chips, muck, shuffle) and dramatic effects (all-in sting, bust).
// PURE and deterministic — no croupier voice (that is the `SpeechConductor`'s job
// now), no VoiceOver, no probabilistic bot voices (those are stateful and live in
// `AudioDirector`), no ambient (dynamic, also in `AudioDirector`).
//
// Keeping this pure and small means the whole "what physical sound does each
// event make" question is unit-testable in isolation.

import Foundation
import GameWorld
import GameEngine
import Audio

/// One thing to do to the audio engine (non-spoken layer).
public enum SoundCue: Equatable, Sendable {
    case play(SoundID, SoundCategory)
}

/// The three starting bot characters, so the audio layer can pick voicelines that
/// fit each one (used by `AudioDirector`, not here).
public enum BotCharacter: String, Sendable, Equatable {
    case novice, rock, aggressor
}

public enum AudioScore {

    /// The physical/effect sounds for one event. Pure and deterministic.
    public static func cues(for payload: EventPayload, heroSeatID: Int) -> [SoundCue] {
        switch payload {
        case .handBegan:
            return [.play(SoundCatalog.tblShuffle, .table)]
        case .blindPosted:
            return [.play(SoundCatalog.tblChipsSingle, .table)]
        case .holeCardsDealt:
            return [.play(SoundCatalog.tblCardDealSingle, .table)]
        case let .playerActed(_, action):
            return actionCues(action)
        case let .streetOpened(street, _):
            switch street {
            case .flop:         return [.play(SoundCatalog.tblCardsDealFlop, .table)]
            case .turn, .river: return [.play(SoundCatalog.tblCardFlipSingle, .table)]
            case .preflop:      return []
            }
        case .handShown:
            return [.play(SoundCatalog.tblCardFlipSingle, .table)]
        case .potAwarded:
            return [.play(SoundCatalog.tblChipsPotCollect, .table)]
        case let .playerBusted(playerID):
            return [.play(playerID == heroSeatID ? SoundCatalog.fxBustHero : SoundCatalog.fxBustPlayer, .effect)]
        default:
            // sessionBegan/Ended (ambient/final handled by the director), hole
            // cards public, joins/leaves, handEnded → no physical cue here.
            return []
        }
    }

    private static func actionCues(_ action: ActedAction) -> [SoundCue] {
        switch action {
        case .folded:
            return [.play(SoundCatalog.tblMuck, .table)]
        case .checked:
            return []
        case let .called(_, isAllIn):
            return isAllIn ? allInCues() : [.play(SoundCatalog.tblChipsStack, .table)]
        case let .bet(_, _, isAllIn), let .raised(_, _, isAllIn):
            return isAllIn ? allInCues() : [.play(SoundCatalog.tblChipsStack, .table)]
        }
    }

    /// Any all-in: big chips and the dramatic sting (a non-spoken effect). The
    /// croupier's "all-in" line is added separately by the conductor (D-029).
    private static func allInCues() -> [SoundCue] {
        [.play(SoundCatalog.tblChipsBetLarge, .table),
         .play(SoundCatalog.fxAllInDramatic, .effect)]
    }
}
