// BlackjackAudioDirector.swift
// =====================================================================
// The non-spoken consumer of the blackjack stream: a second, independent
// spectator subscription with its own clock (D-023). It never touches
// VoiceOver and never enqueues an announcement.
//
// It carries one thing the poker directors do not: the PRESENCE of the rest
// of the room. There are no other players at a blackjack table mechanically
// — the player faces the house alone — but a casino with nobody in it is a
// poorer place, and for a blind player the room IS the sound of it. So
// between rounds the director occasionally lets a neighbour stack a chip or
// the table murmur. Ambient by category, so an unproduced file is simply
// silence and never an intrusive announcement (D-066).

import Foundation
import GameEngine
import GameWorld
import Audio

/// Chooses, deterministically, when the rest of the room makes itself heard.
///
/// Pure and seeded so a session is reproducible, and sparse on purpose: the
/// point is an inhabited room, not a busy one.
struct BlackjackPresence {
    private var generator: SeededGenerator
    private let chance: Double
    private var lastPlayed: SoundID?

    /// The whole repertoire. Shared across every casino, because no NPC ever
    /// speaks and therefore nothing here carries a place's identity.
    static let repertoire: [SoundID] = [
        SoundCatalog.fxBjPresenceChips,
        SoundCatalog.fxBjPresenceMurmur,
        SoundCatalog.fxBjPresenceCards
    ]

    init(seed: UInt64, chance: Double = 0.28) {
        self.generator = SeededGenerator(seed: seed)
        self.chance = chance
    }

    /// The sound the room makes between one round and the next, if any.
    /// Never repeats the previous one back to back.
    mutating func next() -> SoundID? {
        let roll = Double(generator.next() % 1000) / 1000.0
        guard roll < chance else { return nil }

        var candidates = Self.repertoire.filter { $0 != lastPlayed }
        if candidates.isEmpty { candidates = Self.repertoire }
        let pick = candidates[Int(generator.next() % UInt64(candidates.count))]
        lastPlayed = pick
        return pick
    }
}

@MainActor
public final class BlackjackAudioDirector {

    private let audio: AudioServicing
    private let fastMode: Bool
    private let ambient: AmbientBeds
    private var presence: BlackjackPresence
    private var movement = 0

    public init(audio: AudioServicing,
                fastMode: Bool = false,
                seed: UInt64 = 0,
                ambient: AmbientBeds = .riverwood) {
        self.audio = audio
        self.fastMode = fastMode
        self.ambient = ambient
        self.presence = BlackjackPresence(seed: seed)
    }

    public func run(_ stream: AsyncStream<BlackjackSessionEvent>) async {
        for await event in stream {
            handle(event.payload)
            if !fastMode {
                let seconds = BlackjackPacing.seconds(for: event.payload)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    @discardableResult
    public func handle(_ payload: BlackjackEventPayload) -> [SoundCue] {
        switch payload {
        case .sessionBegan:
            audio.startAmbient(bed(ambient.calm1, ambient.calm1Fallback))
            audio.setAmbientScale(ambient.bedVolume, duration: 1.0)
            audio.startAmbientLayer(bed(ambient.layer, ambient.layerFallback),
                                    volume: ambient.layerIsOccasional ? 0 : ambient.layerVolume)

        case .roundBegan:
            movement += 1
            // The room speaks up between hands, where it costs the player
            // nothing: never during a decision, never over a result.
            if let cue = presence.next() {
                audio.play(cue, category: .botVoice)
            }

        case .sessionEnded:
            audio.stopAll()
            return []

        default:
            break
        }

        let cues = BlackjackAudioScore.cues(for: payload)
        for case let .play(id, category) in cues {
            audio.play(id, category: category)
        }
        return cues
    }

    private func bed(_ preferred: SoundID, _ fallback: SoundID) -> SoundID {
        audio.isAvailable(preferred) ? preferred : fallback
    }
}
