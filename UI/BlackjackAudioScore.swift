// BlackjackAudioScore.swift
// =====================================================================
// The NON-SPOKEN half of the blackjack soundtrack: a pure event → cues
// mapping (D-023/D-028). Nothing here speaks; the spoken channel is the
// `BlackjackSpeechMap`'s business alone.
//
// The physical sounds are the game-neutral ones the whole house already uses
// — chips, cards, shuffles — so a blackjack table sounds like the casino it
// stands in without a single new file.

import Foundation
import GameWorld
import Audio

public enum BlackjackAudioScore {

    public static func cues(for payload: BlackjackEventPayload) -> [SoundCue] {
        switch payload {
        case .sessionBegan:
            return [.play(SoundCatalog.tblShuffle, .table)]

        case .shoeShuffled:
            return [.play(SoundCatalog.tblShuffle, .table)]

        case .roundBegan:
            return [.play(SoundCatalog.tblChipsSingle, .table)]

        case .dealt:
            // Two cards to the player and one to the dealer arrive as one
            // gesture, so they sound like one gesture.
            return [.play(SoundCatalog.tblCardsDealFlop, .table)]

        case .handTurnBegan:
            return []

        case let .playerActed(_, action, _):
            return actionCues(action)

        case let .dealerPlayed(_, _, _, _, _, drew):
            return drew
                ? [.play(SoundCatalog.tblCardFlipSingle, .table),
                   .play(SoundCatalog.tblCardDealSingle, .table)]
                : [.play(SoundCatalog.tblCardFlipSingle, .table)]

        case .handSettled:
            // The win/lose sting is NOT fired here: it carries the result, so
            // it must land AFTER the line that explains it, and it is
            // sequenced on the spoken channel instead (D-085).
            return []

        case let .roundEnded(_, net, _, _):
            return net > 0 ? [.play(SoundCatalog.tblChipsPotCollect, .table)] : []

        case .sessionEnded:
            return []
        }
    }

    private static func actionCues(_ action: BlackjackActedAction) -> [SoundCue] {
        switch action {
        case let .hit(_, _, _, didBust):
            return didBust
                ? [.play(SoundCatalog.tblCardDealSingle, .table),
                   .play(SoundCatalog.fxBustPlayer, .effect)]
                : [.play(SoundCatalog.tblCardDealSingle, .table)]

        case .stood:
            return [.play(SoundCatalog.tblMuck, .table)]

        case let .doubled(_, _, _, didBust):
            var cues: [SoundCue] = [.play(SoundCatalog.tblChipsBetLarge, .table),
                                    .play(SoundCatalog.tblCardDealSingle, .table)]
            if didBust { cues.append(.play(SoundCatalog.fxBustPlayer, .effect)) }
            return cues

        case .split:
            return [.play(SoundCatalog.tblChipsStack, .table),
                    .play(SoundCatalog.tblCardsDealFlop, .table)]

        case .surrendered:
            return [.play(SoundCatalog.tblMuck, .table)]
        }
    }
}

/// How long the table lingers on each event when the app's VoiceOver mode is
/// OFF. Blackjack is a FAST game and these are deliberately short: the
/// rhythm the sighted player enjoys is the one the blind player must get too.
enum BlackjackPacing {
    static func seconds(for payload: BlackjackEventPayload) -> Double {
        switch payload {
        case .sessionBegan:   return 0.5
        case .shoeShuffled:   return 0.6
        case .roundBegan:     return 0.25
        case .dealt:          return 0.7
        case .handTurnBegan:  return 0.35
        case .playerActed:    return 0.45
        case .dealerPlayed:   return 0.8
        case .handSettled:    return 0.7
        case .roundEnded:     return 0.5
        case .sessionEnded:   return 0.3
        }
    }
}
