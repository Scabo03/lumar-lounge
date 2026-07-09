// DrawAudioScore.swift
// =====================================================================
// The NON-spoken layer of the Five-Card Draw event → sound mapping (D-044,
// mirrors D-029): physical table sounds (cards, chips, muck, shuffle) and the
// bust sting. PURE and deterministic — no croupier voice (the `SpeechConductor`'s
// job), no VoiceOver, no ambient (dynamic, in `DrawAudioDirector`).

import Foundation
import GameWorld
import GameEngine
import Audio

public enum DrawAudioScore {

    /// The physical/effect sounds for one draw event. Pure and deterministic.
    public static func cues(for payload: DrawEventPayload, heroSeatID: Int) -> [SoundCue] {
        switch payload {
        case .handBegan:
            return [.play(SoundCatalog.tblShuffle, .table)]
        case .antePosted:
            return [.play(SoundCatalog.tblChipsSingle, .table)]
        case .cardsDealt:
            return [.play(SoundCatalog.tblCardDealSingle, .table)]
        case let .playerActed(_, action, _):
            return actionCues(action)
        case let .playerDrew(_, discardCount):
            // Replacement cards are dealt; silent for a stand-pat (zero) draw.
            return discardCount > 0 ? [.play(SoundCatalog.tblCardDealSingle, .table)] : []
        case .passedIn:
            return [.play(SoundCatalog.tblShuffle, .table)]   // cards collected, reshuffled
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

    private static func actionCues(_ action: DrawActedAction) -> [SoundCue] {
        switch action {
        case .folded:
            return [.play(SoundCatalog.tblMuck, .table)]
        case .checked:
            return []
        case let .called(_, isAllIn):
            return isAllIn ? allInCues() : [.play(SoundCatalog.tblChipsStack, .table)]
        case let .bet(_, isAllIn), let .raised(_, isAllIn):
            return isAllIn ? allInCues() : [.play(SoundCatalog.tblChipsStack, .table)]
        }
    }

    private static func allInCues() -> [SoundCue] {
        [.play(SoundCatalog.tblChipsBetLarge, .table),
         .play(SoundCatalog.fxAllInDramatic, .effect)]
    }
}
