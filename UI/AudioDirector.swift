// AudioDirector.swift
// =====================================================================
// The audio consumer: a PARALLEL subscriber to the driver's public event
// stream (peer of the visual consumer), which turns each event into sound via
// the pure `AudioScore` mapping and drives the neutral `Audio` module (D-023).
//
// It paces itself with the SAME rhythm as the visual consumer (`Pacing`), so
// sound stays locked to picture; any within-hand drift resets at each hand
// boundary (both consumers receive the next hand's burst together). It never
// forces the driver's rhythm.
//
// Session start/end sounds (ambient, win/lose jingle) live here too; UI-input
// sounds (button taps) are played directly by the views, not from the stream.

import Foundation
import GameWorld
import GameEngine
import Audio

/// Shared human-pacing between the visual and audio consumers.
enum Pacing {
    static func seconds(for payload: EventPayload) -> Double {
        switch payload {
        case .sessionBegan: return 0.6
        case .handBegan: return 0.8
        case .blindPosted: return 0.45
        case .holeCardsDealt: return 0.2
        case .playerActed: return 0.65
        case .streetOpened: return 0.7
        case .handShown: return 1.0
        case .potAwarded: return 1.2
        case .handEnded: return 1.4
        case .playerBusted: return 1.0
        case .sessionEnded: return 0.0
        default: return 0.3
        }
    }
}

@MainActor
public final class AudioDirector {

    private let audio: AudioServicing
    private let heroSeatID: Int
    private let voices: [Int: BotVoiceProfile]
    private var rng: SeededGenerator
    private let fastMode: Bool
    private var heroChips: Int?

    public init(audio: AudioServicing, heroSeatID: Int, voices: [Int: BotVoiceProfile],
                seed: UInt64, fastMode: Bool = false) {
        self.audio = audio
        self.heroSeatID = heroSeatID
        self.voices = voices
        self.rng = SeededGenerator(seed: seed)
        self.fastMode = fastMode
    }

    /// Consumes the stream to the end, playing sounds at human pace.
    public func run(_ stream: AsyncStream<SessionEvent>) async {
        for await event in stream {
            if Task.isCancelled { break }
            handle(event.payload)
            await pause(Pacing.seconds(for: event.payload))
        }
    }

    /// Processes one event: plays its cues, and handles the session-end jingle.
    /// Returns the cues it played (useful for tests).
    @discardableResult
    public func handle(_ payload: EventPayload) -> [SoundCue] {
        if case let .handEnded(_, _, _, _, chips) = payload {
            heroChips = chips[heroSeatID]
        }
        if case .sessionEnded = payload {
            let won = (heroChips ?? 0) > 0
            audio.play(won ? SoundCatalog.fxWinGame : SoundCatalog.fxLoseGame, category: .effect)
            audio.stopAll()
            return []
        }

        let cues = AudioScore.cues(for: payload, heroSeatID: heroSeatID, voices: voices, rng: &rng)
        for cue in cues {
            switch cue {
            case let .startAmbient(id): audio.startAmbient(id)
            case let .play(id, category): audio.play(id, category: category)
            }
        }
        return cues
    }

    private func pause(_ seconds: Double) async {
        let effective = fastMode ? 0.01 : seconds
        guard effective > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(effective * 1_000_000_000))
    }
}
