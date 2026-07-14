// StudAudioDirector.swift
// =====================================================================
// The NON-spoken audio consumer for the ClockTower's Stud table (D-077, mirrors the
// other directors): a parallel spectator subscriber that plays the physical table
// sounds/effects (via the pure `StudAudioScore`), drives the DYNAMIC AMBIENT — the
// ClockTower's erudite CLASSICAL bed (strings), tense on an all-in, hushed at showdown,
// restored after the pot — and plays the hero's hand-end reaction.
//
// It plays no croupier voice and posts no VoiceOver — those speaking systems are the
// `SpeechConductor`'s. Ambient beds fall back to lounge beds until the ClockTower files
// are produced (StableAudio).

import Foundation
import GameWorld
import GameEngine
import Audio

/// Shared human pacing for the Stud consumers.
enum StudPacing {
    static func seconds(for payload: StudEventPayload) -> Double {
        switch payload {
        case .sessionBegan: return 0.6
        case .handBegan: return 0.7
        case .antePosted: return 0.15
        case .holeCardsDealt: return 0.2
        case .privateDownCards: return 0.55
        case .upCardDealt: return 0.5
        case .bringInPosted: return 0.4
        case .streetBegan: return 0.35
        case .playerActed: return 0.55
        case .handShown: return 1.0
        case .potAwarded: return 1.1
        case .housePrizeAwarded: return 1.0
        case .handEnded: return 1.2
        case .playerBusted: return 1.0
        default: return 0.3
        }
    }
}

@MainActor
public final class StudAudioDirector {

    private let audio: AudioServicing
    private let heroSeatID: Int
    private let fastMode: Bool
    private let ambient: AmbientBeds

    private var startChips: [Int: Int] = [:]
    private var allInInPlay = false
    private var showdownHushed = false

    public init(audio: AudioServicing, heroSeatID: Int, fastMode: Bool = false, ambient: AmbientBeds = .clocktower) {
        self.audio = audio
        self.heroSeatID = heroSeatID
        self.fastMode = fastMode
        self.ambient = ambient
    }

    public func run(_ stream: AsyncStream<StudSessionEvent>) async {
        for await event in stream {
            if Task.isCancelled { break }
            handle(event.payload)
            await pause(StudPacing.seconds(for: event.payload))
        }
    }

    @discardableResult
    public func handle(_ payload: StudEventPayload) -> [SoundCue] {
        switch payload {
        case let .sessionBegan(seats, _, _, _):
            audio.startAmbient(calmBed)
            audio.startAmbientLayer(bed(ambient.layer, ambient.layerFallback), volume: ambient.layerVolume)
            for s in seats { startChips[s.seatID] = s.chips }

        case let .handBegan(_, _, _, _, seats):
            allInInPlay = false
            showdownHushed = false
            for s in seats { startChips[s.seatID] = s.chips }
            audio.setAmbientScale(1.0, duration: 0.3)
            audio.crossfadeAmbient(to: calmBed, duration: 0.8)

        case let .playerActed(_, action):
            if StudSpeechMap.isAllIn(action), !allInInPlay {
                allInInPlay = true
                audio.crossfadeAmbient(to: tenseBed, duration: 0.8)
            }

        case .handShown:
            hushForShowdown()

        case .potAwarded:
            restoreAmbientAfterShowdown()

        case let .handEnded(_, _, _, chips):
            heroChipDeltaFeedback(chips)
            allInInPlay = false

        case .sessionEnded:
            let heroFinal = startChips[heroSeatID] ?? 0
            audio.play(heroFinal > 0 ? SoundCatalog.fxVictoryFinal : SoundCatalog.fxDefeatFinal, category: .effect)
            audio.stopAll()
            return []

        default:
            break
        }

        let cues = StudAudioScore.cues(for: payload, heroSeatID: heroSeatID)
        for case let .play(id, category) in cues { audio.play(id, category: category) }
        return cues
    }

    private var calmBed: SoundID { bed(ambient.calm1, ambient.calm1Fallback) }
    private var tenseBed: SoundID { bed(ambient.tense, ambient.tenseFallback) }

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
        if allInInPlay { audio.crossfadeAmbient(to: calmBed, duration: 1.0) }
    }

    private func heroChipDeltaFeedback(_ chips: [Int: Int]) {
        guard let start = startChips[heroSeatID], let final = chips[heroSeatID] else { return }
        let fx = final > start ? SoundCatalog.fxWinHand
               : (final < start ? SoundCatalog.fxLoseHand : SoundCatalog.fxHandNeutral)
        audio.play(fx, category: .effect)
    }

    private func bed(_ preferred: SoundID, _ fallback: SoundID) -> SoundID {
        audio.isAvailable(preferred) ? preferred : fallback
    }

    private func pause(_ seconds: Double) async {
        let effective = fastMode ? 0.01 : seconds
        guard effective > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(effective * 1_000_000_000))
    }
}
