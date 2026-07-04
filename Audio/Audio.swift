// Audio
// =====================================================================
// Cross-cutting sound system. Transversal and GAME-AGNOSTIC (D-023): it knows
// nothing about poker, events, seats or rules. It plays opaque, caller-defined
// sounds grouped into categories, and it owns the one piece of accessibility
// policy that belongs to the audio layer itself: never talk over VoiceOver.
//
// It may import AVFoundation (its raison d'être) and, only for VoiceOver
// detection, UIKit under `#if canImport(UIKit)`. It must NOT import GameEngine,
// GameWorld or UI: whoever knows the game (UI) maps events to these opaque
// sounds and drives this module.

import Foundation

/// An opaque identifier for a sound: the base file name (without extension) of a
/// bundled audio resource. The audio layer never interprets its meaning.
public struct SoundID: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// The kind of sound, which decides its default volume and whether it is a
/// SPOKEN sound that must yield to VoiceOver.
public enum SoundCategory: String, CaseIterable, Sendable {
    /// Looping background atmosphere.
    case ambient
    /// Physical table effects (cards, chips). Non-spoken.
    case table
    /// The croupier's spoken lines. SPOKEN → yields to VoiceOver.
    case croupier
    /// The bots' spoken lines. SPOKEN → yields to VoiceOver.
    case botVoice
    /// Dramatic outcome feedback (win/lose/all-in). Non-spoken.
    case effect
    /// UI feedback for direct user input (taps). Non-spoken.
    case ui

    /// Spoken categories would collide with VoiceOver's own speech.
    public var isSpoken: Bool { self == .croupier || self == .botVoice }

    /// Default gain 0…1 for the category (tuned to be present but not invasive).
    public var defaultVolume: Float {
        switch self {
        case .ambient: return 0.35
        case .table: return 0.8
        case .croupier: return 1.0
        case .botVoice: return 0.9
        case .effect: return 0.95
        case .ui: return 0.7
        }
    }
}

/// The single accessibility rule the audio layer enforces (D-024): when
/// VoiceOver is speaking, spoken sounds (croupier/bot voices) stay silent so the
/// two voices never overlap. Everything non-spoken keeps playing.
public enum AudioPolicy {
    public static func shouldPlay(_ category: SoundCategory, voiceOverRunning: Bool) -> Bool {
        if voiceOverRunning && category.isSpoken { return false }
        return true
    }
}

/// The generic audio interface the rest of the app depends on. Driven by opaque
/// sounds; unaware of poker. In practice its callers (UI) are on the main actor,
/// so implementations are effectively main-confined, but the protocol is left
/// non-isolated to avoid friction constructing it from SwiftUI `init`s.
public protocol AudioServicing: AnyObject {
    /// Starts (or replaces) the looping ambient bed.
    func startAmbient(_ id: SoundID)
    /// Plays a one-shot sound, overlapping whatever else is playing.
    func play(_ id: SoundID, category: SoundCategory)
    /// Stops the ambient bed and all one-shots.
    func stopAll()
    /// Master volume 0…1 applied on top of per-category volumes.
    func setMasterVolume(_ volume: Float)
    /// Mutes/unmutes everything.
    func setMuted(_ muted: Bool)
}

/// A do-nothing implementation for tests, previews, and platforms without audio.
public final class NullAudioService: AudioServicing {
    public init() {}
    public func startAmbient(_ id: SoundID) {}
    public func play(_ id: SoundID, category: SoundCategory) {}
    public func stopAll() {}
    public func setMasterVolume(_ volume: Float) {}
    public func setMuted(_ muted: Bool) {}
}

/// Namespace and metadata for the audio layer.
public enum Audio {
    /// Semantic version of the audio layer.
    public static let version = "1.0.0"
}
