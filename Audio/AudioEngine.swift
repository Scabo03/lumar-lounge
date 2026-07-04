// AudioEngine.swift
// =====================================================================
// The real AVFoundation implementation of `AudioServicing`: one looping ambient
// player plus overlapping one-shots, per-category volumes, a master volume and
// mute, and the VoiceOver rule (spoken sounds stay silent while VoiceOver runs,
// D-024).
//
// Degrades gracefully: a sound whose file is missing from the bundle simply
// doesn't play (the app is fully usable with partial or no audio), and the set
// of missing files is logged once at startup.
//
// AVFoundation is available on macOS too, so this compiles for `swift test`;
// `AVAudioSession` (iOS-only) and `UIAccessibility` (VoiceOver) are guarded.

import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

public final class AudioEngine: AudioServicing {

    /// How many one-shot players are kept alive at once. Older ones (long
    /// finished, since sounds are short) are released as new ones start — a
    /// simple bound that avoids any async cleanup and its races.
    private let maxOverlap = 12

    private let bundle: Bundle
    private let fileExtension: String
    private var ambientPlayer: AVAudioPlayer?
    private var oneShots: [AVAudioPlayer] = []
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
        guard AudioPolicy.shouldPlay(category, voiceOverRunning: isVoiceOverRunning) else { return }
        guard !muted, let player = makePlayer(id) else { return }
        player.volume = gain(for: category)
        player.prepareToPlay()
        player.play()
        oneShots.append(player)
        if oneShots.count > maxOverlap { oneShots.removeFirst() }
    }

    public func stopAll() {
        ambientPlayer?.stop()
        ambientPlayer = nil
        oneShots.forEach { $0.stop() }
        oneShots.removeAll()
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

    private var isVoiceOverRunning: Bool {
        #if canImport(UIKit)
        return UIAccessibility.isVoiceOverRunning
        #else
        return false
        #endif
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
