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
    /// VoiceOver's start latency after focus lands on the hand — the beat before it
    /// actually begins reading, which the dealer reveal must clear too (D-097). Raised
    /// generously in D-100: on the device the read STARTS several hundred ms to a
    /// second after focus lands, so a small lead let the dealer announcement fire
    /// mid-read again. The wait must cover the latency AND the read.
    static let focusReadLead: Double = 2.0

    /// The dealer's card is held back until the hand's focus-landing read is
    /// expected to have FINISHED, not for a fixed guess (D-097). Focus lands on
    /// the hand and VoiceOver reads its whole label — total and cards — so the
    /// wait is that read's estimated length plus the start latency, and it scales
    /// with the hand (a two-card seventeen is shorter than a split of tens). A
    /// fixed 2.5 s (D-096) was sometimes too short and cut the read off.
    @MainActor
    static func dealerRevealDelay(afterReading handLine: String) -> Double {
        focusReadLead + AnnouncementQueue.speakTime(handLine)
    }

    /// A floor beat before the next wager box opens, so a round that just settled is
    /// actually in flight and heard before the box's focus landing interrupts it
    /// (D-097). Raised to give the end-of-hand line room to be understood before the
    /// pop-up arrives (D-100) — the reported "arrives before I've grasped what
    /// happened". The box then ALSO waits for the channel to fall fully quiet.
    static let betBoxLeadIn: Double = 3.5

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
