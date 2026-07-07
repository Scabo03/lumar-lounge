// SpeechCoordinator.swift
// =====================================================================
// The audio ⇄ VoiceOver timing rule (D-028), kept as a pure, testable function.
//
// Strategy C gives the croupier and VoiceOver separate domains, but they can
// still land close in time (the croupier says "flop", then it's the human's
// turn). The rule: VoiceOver waits for a croupier/bot voice that is still
// playing to finish — plus a small gap — before it speaks, so the two speaking
// systems never overlap. One direction only (VoiceOver yields to the croupier,
// the metronome of the game), which keeps the mechanism simple.

import Foundation

enum SpeechCoordinator {

    /// A short silence left after a spoken cue before VoiceOver starts, so the two
    /// don't butt right up against each other.
    static let gap: TimeInterval = 0.15

    /// How long VoiceOver should wait, given the spoken audio still playing.
    /// Zero when nothing spoken is playing (the common case → no added latency).
    static func voiceOverDelay(spokenRemaining: TimeInterval) -> TimeInterval {
        spokenRemaining > 0 ? spokenRemaining + gap : 0
    }
}
