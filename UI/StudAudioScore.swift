// StudAudioScore.swift
// =====================================================================
// The NON-spoken layer of the Stud event → sound mapping (D-077, mirrors the other
// tables' `AudioScore`): physical table sounds (cards, chips, muck, shuffle) and the bust
// sting. PURE and deterministic — no croupier voice (the `SpeechConductor`'s job), no
// VoiceOver, no ambient (dynamic, in `StudAudioDirector`). The physical sounds are
// game-neutral and shared with the other tables.

import Foundation
import GameWorld
import GameEngine
import Audio

public enum StudAudioScore {

    /// The physical/effect sounds for one Stud event. Pure and deterministic.
    public static func cues(for payload: StudEventPayload, heroSeatID: Int) -> [SoundCue] {
        switch payload {
        case .handBegan:
            return [.play(SoundCatalog.tblShuffle, .table)]
        case .antePosted:
            return [.play(SoundCatalog.tblChipsSingle, .table)]
        case .holeCardsDealt:
            return [.play(SoundCatalog.tblCardDealSingle, .table)]
        case .upCardDealt, .communityCardDealt:
            return [.play(SoundCatalog.tblCardFlipSingle, .table)]
        case .bringInPosted:
            return [.play(SoundCatalog.tblChipsSingle, .table)]
        case let .playerActed(_, action):
            return actionCues(action)
        case .handShown:
            return [.play(SoundCatalog.tblCardFlipSingle, .table)]
        case .potAwarded:
            return [.play(SoundCatalog.tblChipsPotCollect, .table)]
        case let .playerBusted(playerID):
            return [.play(playerID == heroSeatID ? SoundCatalog.fxBustHero : SoundCatalog.fxBustPlayer, .effect)]
        default:
            return []
        }
    }

    private static func actionCues(_ action: StudActedAction) -> [SoundCue] {
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

    private static func allInCues() -> [SoundCue] {
        [.play(SoundCatalog.tblChipsBetLarge, .table),
         .play(SoundCatalog.fxAllInDramatic, .effect)]
    }
}
