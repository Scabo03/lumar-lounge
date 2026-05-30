// Audio
// =====================================================================
// Cross-cutting sound and haptics system.
//
// RULE: this module is transversal. It must know NOTHING about poker,
// blackjack or any specific game. It exposes a generic interface that the
// rest of the project drives via opaque, caller-defined identifiers.
//
// It deliberately does not depend on GameEngine, GameWorld or UI.
// No playback is implemented yet — this is scaffolding only.

import Foundation

/// An opaque identifier for a sound effect. Callers define their own values;
/// the audio layer never interprets the meaning of the identifier.
public struct SoundID: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// An opaque identifier for a music track.
public struct MusicID: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// An opaque identifier for a haptic pattern.
public struct HapticID: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// Generic, game-agnostic audio and haptics interface that the rest of the
/// project can depend on without knowing how playback is implemented.
public protocol AudioServicing: AnyObject {
    func playSound(_ id: SoundID)
    func playMusic(_ id: MusicID)
    func stopMusic()
    func playHaptic(_ id: HapticID)
    func setMuted(_ muted: Bool)
}

/// A do-nothing implementation, useful as a default and for previews/tests.
/// Real playback (AVFoundation / CoreHaptics) will be added behind this same
/// protocol later, so callers never change.
public final class NullAudioService: AudioServicing {
    public init() {}
    public func playSound(_ id: SoundID) {}
    public func playMusic(_ id: MusicID) {}
    public func stopMusic() {}
    public func playHaptic(_ id: HapticID) {}
    public func setMuted(_ muted: Bool) {}
}

/// Namespace and metadata for the audio layer.
public enum Audio {
    /// Semantic version of the audio layer.
    public static let version = "0.1.0"
}
