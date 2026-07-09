// DrawAudioDirector.swift
// =====================================================================
// The NON-spoken audio consumer for the Five-Card Draw table (D-044, mirrors the
// Texas `AudioDirector`): a parallel spectator subscriber that plays the physical
// table sounds/effects (via the pure `DrawAudioScore`), drives the DYNAMIC AMBIENT
// (Riverwood calm ↔ tense on a swollen progressive pot or an all-in, hush at
// showdown), and plays the bots' hand-end reactions.
//
// It plays no croupier voice and posts no VoiceOver — those SPEAKING systems are
// the `SpeechConductor`'s. It paces itself with the same rhythm as the display.

import Foundation
import GameWorld
import GameEngine
import Audio

/// Shared human pacing for the draw consumers.
enum DrawPacing {
    static func seconds(for payload: DrawEventPayload) -> Double {
        switch payload {
        case .sessionBegan: return 0.6
        case .handBegan: return 0.7
        case .antePosted: return 0.3
        case .cardsDealt: return 0.2
        case .playerActed: return 0.6
        case .potOpened: return 0.2
        case .passedIn: return 1.2
        case .drawPhaseBegan: return 0.6
        case .playerDrew: return 0.6
        case .privateDrawnCards: return 0.5
        case .secondBetBegan: return 0.3
        case .handShown: return 1.0
        case .openersDisqualified: return 1.2
        case .potAwarded: return 1.2
        case .handEnded: return 1.3
        case .playerBusted: return 1.0
        default: return 0.3
        }
    }
}

@MainActor
public final class DrawAudioDirector {

    private let audio: AudioServicing
    private let heroSeatID: Int
    private let characters: [Int: BotCharacter]
    private var rng: SeededGenerator
    private let fastMode: Bool

    private var startChips: [Int: Int] = [:]
    private var basePot = 0
    private var allInInPlay = false
    private var showdownHushed = false

    public init(audio: AudioServicing, heroSeatID: Int, characters: [Int: BotCharacter],
                seed: UInt64, fastMode: Bool = false) {
        self.audio = audio
        self.heroSeatID = heroSeatID
        self.characters = characters
        self.rng = SeededGenerator(seed: seed)
        self.fastMode = fastMode
    }

    public func run(_ stream: AsyncStream<DrawSessionEvent>) async {
        for await event in stream {
            if Task.isCancelled { break }
            handle(event.payload)
            await pause(DrawPacing.seconds(for: event.payload))
        }
    }

    @discardableResult
    public func handle(_ payload: DrawEventPayload) -> [SoundCue] {
        switch payload {
        case let .sessionBegan(seats, ante, _, _):
            audio.startAmbient(bed(SoundCatalog.ambRiverwoodCalm1, SoundCatalog.ambLoungeCalm1))
            audio.startAmbientLayer(SoundCatalog.ambCrowdDistant, volume: 0.2)
            for s in seats { startChips[s.seatID] = s.chips }
            basePot = ante * max(1, seats.count)

        case let .handBegan(_, _, _, _, _, _, carriedPot, seats):
            allInInPlay = false
            showdownHushed = false
            for s in seats { startChips[s.seatID] = s.chips }
            audio.setAmbientScale(1.0, duration: 0.3)
            // A swollen progressive pot (more than double the base) raises the tension.
            let tense = carriedPot > 2 * basePot
            audio.crossfadeAmbient(to: tense ? SoundCatalog.ambLoungeTense
                                             : bed(SoundCatalog.ambRiverwoodCalm1, SoundCatalog.ambLoungeCalm1),
                                   duration: 0.8)

        case let .playerActed(_, action, _):
            if DrawSpeechMap.isAllIn(action), !allInInPlay {
                allInInPlay = true
                audio.crossfadeAmbient(to: SoundCatalog.ambLoungeTense, duration: 0.8)
            }

        case .handShown:
            hushForShowdown()

        case .potAwarded:
            restoreAmbientAfterShowdown()

        case let .handEnded(_, _, chips):
            heroChipDeltaFeedback(chips)
            botHandEndVoicelines(chips)
            allInInPlay = false

        case .sessionEnded:
            let heroFinal = startChips[heroSeatID] ?? 0
            audio.play(heroFinal > 0 ? SoundCatalog.fxVictoryFinal : SoundCatalog.fxDefeatFinal, category: .effect)
            audio.stopAll()
            return []

        default:
            break
        }

        let cues = DrawAudioScore.cues(for: payload, heroSeatID: heroSeatID)
        for case let .play(id, category) in cues { audio.play(id, category: category) }
        return cues
    }

    private func hushForShowdown() {
        guard !showdownHushed else { return }
        showdownHushed = true
        audio.setAmbientScale(0.35, duration: 0.5)
        audio.play(SoundCatalog.ambSilenceTension, category: .ambient)
    }

    private func restoreAmbientAfterShowdown() {
        guard showdownHushed || allInInPlay else { return }
        showdownHushed = false
        audio.setAmbientScale(1.0, duration: 0.5)
        if allInInPlay {
            audio.crossfadeAmbient(to: bed(SoundCatalog.ambRiverwoodCalm1, SoundCatalog.ambLoungeCalm1), duration: 1.0)
        }
    }

    private func heroChipDeltaFeedback(_ chips: [Int: Int]) {
        guard let start = startChips[heroSeatID], let final = chips[heroSeatID] else { return }
        let fx = final > start ? SoundCatalog.fxWinHand
               : (final < start ? SoundCatalog.fxLoseHand : SoundCatalog.fxHandNeutral)
        audio.play(fx, category: .effect)
    }

    private func botHandEndVoicelines(_ chips: [Int: Int]) {
        for (seat, character) in characters where character == .novice {
            guard let start = startChips[seat], let final = chips[seat] else { continue }
            if final > start, roll() < 0.5 {
                audio.play(SoundCatalog.vobNoviceExcited, category: .botVoice)
            } else if final < start, roll() < 0.4 {
                audio.play(SoundCatalog.vobNoviceDisappointed, category: .botVoice)
            }
        }
    }

    /// The preferred bed if bundled, else a lounge fallback (D-035/D-030).
    private func bed(_ preferred: SoundID, _ fallback: SoundID) -> SoundID {
        audio.isAvailable(preferred) ? preferred : fallback
    }

    private func roll() -> Double {
        Double(rng.next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    private func pause(_ seconds: Double) async {
        let effective = fastMode ? 0.01 : seconds
        guard effective > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(effective * 1_000_000_000))
    }
}
