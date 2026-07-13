// OmahaAudioDirector.swift
// =====================================================================
// The NON-spoken audio consumer for the Skypool's Omaha table (D-066, mirrors the
// Texas/Draw directors): a parallel spectator subscriber that plays the physical table
// sounds/effects (via the pure `OmahaAudioScore`), drives the DYNAMIC AMBIENT — the
// Skypool's cool urban bed, tense on an all-in or a stake escalation, hushed at
// showdown — and plays the bots' hand-end reactions (Skypool urban colour, silent
// until produced, D-066).
//
// It plays no croupier voice and posts no VoiceOver — those speaking systems are the
// `SpeechConductor`'s. Ambient beds fall back to lounge beds until the Skypool files
// are produced (StableAudio).

import Foundation
import GameWorld
import GameEngine
import Audio

/// Shared human pacing for the Omaha consumers.
enum OmahaPacing {
    static func seconds(for payload: OmahaEventPayload) -> Double {
        switch payload {
        case .sessionBegan: return 0.6
        case .handBegan: return 0.7
        case .stakesEscalated: return 0.9
        case .blindPosted: return 0.3
        case .holeCardsDealt: return 0.2
        case .privateHoleCards: return 0.6
        case .playerActed: return 0.6
        case .streetOpened: return 0.5
        case .handShown: return 1.0
        case .potAwarded: return 1.2
        case .handEnded: return 1.3
        case .playerBusted: return 1.0
        default: return 0.3
        }
    }
}

@MainActor
public final class OmahaAudioDirector {

    private let audio: AudioServicing
    private let heroSeatID: Int
    private let characters: [Int: BotCharacter]
    private var rng: SeededGenerator
    private let fastMode: Bool

    private var startChips: [Int: Int] = [:]
    private var allInInPlay = false
    private var showdownHushed = false
    private var activeSeats: Set<Int> = []
    private var bustedSeats: Set<Int> = []
    /// The hosting casino's ambient beds and bot colour voices (D-067); default Skypool.
    private let ambient: AmbientBeds
    private let voices: BotVoices

    public init(audio: AudioServicing, heroSeatID: Int, characters: [Int: BotCharacter],
                seed: UInt64, fastMode: Bool = false,
                ambient: AmbientBeds = .skypool, voices: BotVoices = .skypool) {
        self.audio = audio
        self.heroSeatID = heroSeatID
        self.characters = characters
        self.rng = SeededGenerator(seed: seed)
        self.fastMode = fastMode
        self.ambient = ambient
        self.voices = voices
    }

    public func run(_ stream: AsyncStream<OmahaSessionEvent>) async {
        for await event in stream {
            if Task.isCancelled { break }
            handle(event.payload)
            await pause(OmahaPacing.seconds(for: event.payload))
        }
    }

    @discardableResult
    public func handle(_ payload: OmahaEventPayload) -> [SoundCue] {
        switch payload {
        case let .sessionBegan(seats, _, _):
            audio.startAmbient(calmBed)
            audio.startAmbientLayer(bed(ambient.layer, ambient.layerFallback), volume: 0.18)
            for s in seats { startChips[s.seatID] = s.chips }

        case let .handBegan(_, _, _, _, _, _, _, seats):
            allInInPlay = false
            showdownHushed = false
            activeSeats = Set(seats.map { $0.seatID })   // only these play this hand (D-058)
            for s in seats { startChips[s.seatID] = s.chips }
            audio.setAmbientScale(1.0, duration: 0.3)
            audio.crossfadeAmbient(to: calmBed, duration: 0.8)

        case .stakesEscalated:
            // A stake escalation ratchets the tension up like a decisive hand.
            allInInPlay = true
            audio.crossfadeAmbient(to: tenseBed, duration: 0.8)

        case let .playerActed(_, action):
            if OmahaSpeechMap.isAllIn(action), !allInInPlay {
                allInInPlay = true
                audio.crossfadeAmbient(to: tenseBed, duration: 0.8)
            }

        case .handShown:
            hushForShowdown()

        case .potAwarded:
            restoreAmbientAfterShowdown()

        case let .handEnded(_, _, _, _, chips):
            heroChipDeltaFeedback(chips)
            botHandEndVoicelines(chips)
            allInInPlay = false

        case let .playerBusted(playerID):
            bustedSeats.insert(playerID)   // never voice this seat again (D-058)

        case .sessionEnded:
            let heroFinal = startChips[heroSeatID] ?? 0
            audio.play(heroFinal > 0 ? SoundCatalog.fxVictoryFinal : SoundCatalog.fxDefeatFinal, category: .effect)
            audio.stopAll()
            return []

        default:
            break
        }

        let cues = OmahaAudioScore.cues(for: payload, heroSeatID: heroSeatID)
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

    private func botHandEndVoicelines(_ chips: [Int: Int]) {
        for (seat, character) in characters
        where character == .novice && activeSeats.contains(seat) && !bustedSeats.contains(seat) {
            guard let start = startChips[seat], let final = chips[seat] else { continue }
            if final > start, roll() < 0.5 {
                audio.play(voices.noviceExcited, category: .botVoice)
            } else if final < start, roll() < 0.4 {
                audio.play(voices.noviceDisappointed, category: .botVoice)
            }
        }
    }

    /// The preferred bed if bundled, else a fallback (D-035/D-066).
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
