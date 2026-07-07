// SpeechConductor.swift
// =====================================================================
// The serial owner of the two SPEAKING systems (D-029): the pre-recorded croupier
// voice and the VoiceOver synthesizer. Everything spoken goes through here, one
// item at a time, so the two never overlap and — for a "flop" then its cards — the
// croupier mp3 finishes before the synthesis starts.
//
// It also de-dupes the once-per-hand croupier lines (showdown, pot awarded/split):
// a hand with side pots emits several `potAwarded` events, and playing the pot
// voice for each was the "broken record" bug. Here the voice plays at most once
// per hand; each event's synthesis still speaks its own detail.
//
// Coordination uses the engine's completion handler (AVAudioPlayerDelegate), not a
// fixed delay: the synthesis starts exactly when the croupier line ends. It runs
// alongside the paced display (fire-and-forget) so it never slows the visuals.

import Foundation
import Audio

@MainActor
public final class SpeechConductor {

    private struct Item { let croupier: SoundID?; let synthesis: String? }

    private let audio: AudioServicing
    private let announcer: Announcer

    private var queue: [Item] = []
    private var isSpeaking = false
    private var oncePerHandPlayed: Set<String> = []

    /// Croupier voices that must play at most once per hand.
    private static let oncePerHand: Set<String> = [
        SoundCatalog.voShowdown.rawValue,
        SoundCatalog.voPotAwarded.rawValue,
        SoundCatalog.voSplitPot.rawValue,
    ]

    public init(audio: AudioServicing, announcer: Announcer = Announcer()) {
        self.audio = audio
        self.announcer = announcer
    }

    /// Resets the per-hand de-dup at the start of each hand.
    public func handBegan() { oncePerHandPlayed.removeAll() }

    /// Enqueues a spoken item (a croupier line and/or a synthesis line). Drops a
    /// once-per-hand croupier line if it already played this hand — the fix for the
    /// repeated pot-awarded voice.
    public func say(croupier: SoundID?, synthesis: String?) {
        var croupier = croupier
        if let c = croupier, Self.oncePerHand.contains(c.rawValue) {
            if oncePerHandPlayed.contains(c.rawValue) {
                croupier = nil
            } else {
                oncePerHandPlayed.insert(c.rawValue)
            }
        }
        guard croupier != nil || synthesis != nil else { return }
        queue.append(Item(croupier: croupier, synthesis: synthesis))
        pump()
    }

    /// Test hook: how many times a once-per-hand voice would still be admitted.
    public func admits(_ id: SoundID) -> Bool {
        !(Self.oncePerHand.contains(id.rawValue) && oncePerHandPlayed.contains(id.rawValue))
    }

    private func pump() {
        guard !isSpeaking, !queue.isEmpty else { return }
        isSpeaking = true
        let item = queue.removeFirst()
        Task { await self.process(item) }
    }

    private func process(_ item: Item) async {
        if let croupier = item.croupier {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                audio.play(croupier, category: .croupier) { cont.resume() }
            }
        }
        if let synthesis = item.synthesis {
            announcer.announce(synthesis)
            await pause(synthesisDuration(for: synthesis))
        }
        isSpeaking = false
        pump()
    }

    /// A rough spoken-duration estimate so the next item doesn't start over an
    /// ongoing VoiceOver line. Zero when VoiceOver is off (nothing is spoken).
    private func synthesisDuration(for text: String) -> TimeInterval {
        guard announcer.isVoiceOverRunning else { return 0 }
        return max(0.8, Double(text.count) * 0.06)
    }

    private func pause(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
