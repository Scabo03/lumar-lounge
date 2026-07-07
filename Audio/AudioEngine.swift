// AudioEngine.swift
// =====================================================================
// The real AVFoundation implementation of `AudioServicing`: one looping ambient
// player plus overlapping one-shots, per-category volumes, a master volume and
// mute. Spoken cues (croupier/bot) always play; the engine tracks them so the
// VoiceOver layer can wait for them via `spokenAudioRemaining()` (D-028).
//
// Degrades gracefully: a sound whose file is missing from the bundle simply
// doesn't play (the app is fully usable with partial or no audio), and the set
// of missing files is logged once at startup.
//
// AVFoundation is available on macOS too, so this compiles for `swift test`;
// `AVAudioSession` (iOS-only) is guarded.

import Foundation
import AVFoundation

public final class AudioEngine: AudioServicing {

    /// How many one-shot players are kept alive at once. Older ones (long
    /// finished, since sounds are short) are released as new ones start — a
    /// simple bound that avoids any async cleanup and its races.
    private let maxOverlap = 12

    private let bundle: Bundle
    private let fileExtension: String
    private var ambientPlayer: AVAudioPlayer?
    private var oneShots: [AVAudioPlayer] = []
    /// The most recent spoken (croupier/bot) players, kept so we can report how
    /// much spoken audio is still playing to the VoiceOver layer (D-028).
    private var spokenPlayers: [AVAudioPlayer] = []
    private var masterVolume: Float = 1.0
    private var muted: Bool = false

    public init(bundle: Bundle = .main, fileExtension: String = "mp3", configureSession: Bool = true) {
        self.bundle = bundle
        self.fileExtension = fileExtension
        #if os(iOS)
        if configureSession { Self.configureAudioSession() }
        #endif
        logMissingSounds()
    }

    // MARK: - AudioServicing

    public func startAmbient(_ id: SoundID) {
        ambientPlayer?.stop()
        guard let player = makePlayer(id) else { ambientPlayer = nil; return }
        player.numberOfLoops = -1
        player.volume = gain(for: .ambient)
        player.prepareToPlay()
        player.play()
        ambientPlayer = player
    }

    public func play(_ id: SoundID, category: SoundCategory) {
        // Spoken cues are no longer gated by VoiceOver (D-028): they always play.
        guard !muted, let player = makePlayer(id) else { return }
        player.volume = gain(for: category)
        player.prepareToPlay()
        player.play()
        oneShots.append(player)
        if oneShots.count > maxOverlap { oneShots.removeFirst() }
        if category.isSpoken {
            spokenPlayers.append(player)
            if spokenPlayers.count > 4 { spokenPlayers.removeFirst() }
        }
    }

    /// Seconds of spoken audio still playing (the longest remaining voice), else 0.
    public func spokenAudioRemaining() -> TimeInterval {
        spokenPlayers.reduce(0) { longest, player in
            guard player.isPlaying else { return longest }
            return max(longest, player.duration - player.currentTime)
        }
    }

    public func stopAll() {
        ambientPlayer?.stop()
        ambientPlayer = nil
        oneShots.forEach { $0.stop() }
        oneShots.removeAll()
        spokenPlayers.removeAll()
    }

    public func setMasterVolume(_ volume: Float) {
        masterVolume = min(1, max(0, volume))
        ambientPlayer?.volume = gain(for: .ambient)
    }

    public func setMuted(_ muted: Bool) {
        self.muted = muted
        ambientPlayer?.volume = gain(for: .ambient)
    }

    // MARK: - Diagnostics

    /// Sounds from the catalog whose file is not present in the bundle.
    public func missingSounds() -> [SoundID] {
        SoundCatalog.all.compactMap { url(for: $0.id) == nil ? $0.id : nil }
    }

    private func logMissingSounds() {
        let missing = missingSounds()
        guard !missing.isEmpty else { return }
        print("[Audio] \(missing.count)/\(SoundCatalog.all.count) sound files missing from the bundle "
              + "(audio will be partial). Missing: \(missing.map(\.rawValue).joined(separator: ", "))")
    }

    // MARK: - Helpers

    private func url(for id: SoundID) -> URL? {
        // Resources may be flattened into the bundle root or kept under an
        // "Audio" subdirectory, depending on how Xcode copies them — try both.
        bundle.url(forResource: id.rawValue, withExtension: fileExtension)
            ?? bundle.url(forResource: id.rawValue, withExtension: fileExtension, subdirectory: "Audio")
    }

    private func makePlayer(_ id: SoundID) -> AVAudioPlayer? {
        guard let url = url(for: id) else { return nil }
        return try? AVAudioPlayer(contentsOf: url)
    }

    private func gain(for category: SoundCategory) -> Float {
        muted ? 0 : category.defaultVolume * masterVolume
    }

    #if os(iOS)
    private static func configureAudioSession() {
        // `.ambient` respects the silent switch and, with `.mixWithOthers`, lets
        // VoiceOver speak over our sounds rather than ducking it.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
    #endif
}
