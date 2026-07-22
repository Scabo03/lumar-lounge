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

@MainActor
public final class BlackjackAudioDirector {

    private let audio: AudioServicing
    private let fastMode: Bool
    private let ambient: AmbientBeds
    /// When the rest of the room makes itself heard (now the shared
    /// `TablePresence`, extracted for roulette in D-104 — same algorithm).
    private var presence: TablePresence
    private var movement = 0

    /// This session's chip set (D-104), resolved at play time.
    private let chipSet: TableChipSet

    public init(audio: AudioServicing,
                fastMode: Bool = false,
                seed: UInt64 = 0,
                ambient: AmbientBeds = .riverwood,
                chipSet: TableChipSet = .identity) {
        self.audio = audio
        self.fastMode = fastMode
        self.ambient = ambient
        self.presence = TablePresence(repertoire: TablePresence.blackjack, seed: seed)
        self.chipSet = chipSet
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
            audio.play(chipSet.resolve(id), category: category)
        }
        return cues
    }

    private func bed(_ preferred: SoundID, _ fallback: SoundID) -> SoundID {
        audio.isAvailable(preferred) ? preferred : fallback
    }
}
