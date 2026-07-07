// AudioEngine.swift
// =====================================================================
// The real AVFoundation implementation of `AudioServicing`: a looping ambient
// bed (with crossfades, a low continuous layer, and duck/restore), overlapping
// one-shots, per-category volumes, master volume and mute. Spoken cues always
// play; the engine can report when one finishes (completion handler) so the UI
// can sequence croupier line → VoiceOver synthesis (D-029).
//
// Degrades gracefully: a missing file simply doesn't play (and its completion
// fires immediately, so any sequence still advances). Missing files are logged
// once at startup.
//
// AVFoundation is available on macOS too, so this compiles for `swift test`;
// `AVAudioSession` (iOS-only) is guarded.

import Foundation
import AVFoundation

public final class AudioEngine: NSObject, AudioServicing, AVAudioPlayerDelegate {

    /// How many one-shot players are kept alive at once. Older ones (long
    /// finished, since sounds are short) are released as new ones start.
    private let maxOverlap = 12

    private let bundle: Bundle
    private let fileExtension: String

    private var ambientPlayer: AVAudioPlayer?
    private var ambientLayerPlayer: AVAudioPlayer?
    private var ambientLayerVolume: Float = 0
    private var currentAmbientID: SoundID?
    private var ambientScale: Float = 1.0

    private var oneShots: [AVAudioPlayer] = []
    /// Recent spoken (croupier/bot) players, to report remaining spoken audio.
    private var spokenPlayers: [AVAudioPlayer] = []
    /// Completion handlers keyed by player identity, with the player retained
    /// until it finishes so the callback is never lost to eviction.
    private var completions: [ObjectIdentifier: () -> Void] = [:]
    private var completionPlayers: [ObjectIdentifier: AVAudioPlayer] = [:]

    private var masterVolume: Float = 1.0
    private var muted: Bool = false

    public init(bundle: Bundle = .main, fileExtension: String = "mp3", configureSession: Bool = true) {
        self.bundle = bundle
        self.fileExtension = fileExtension
        super.init()
        #if os(iOS)
        if configureSession { Self.configureAudioSession() }
        #endif
        logMissingSounds()
    }

    // MARK: - Ambient bed

    public func startAmbient(_ id: SoundID) {
        ambientPlayer?.stop()
        currentAmbientID = id
        guard let player = makePlayer(id) else { ambientPlayer = nil; return }
        player.numberOfLoops = -1
        player.volume = ambientGain
        player.prepareToPlay()
        player.play()
        ambientPlayer = player
    }

    public func crossfadeAmbient(to id: SoundID, duration: TimeInterval) {
        guard id != currentAmbientID else { return }
        currentAmbientID = id
        let old = ambientPlayer
        guard let next = makePlayer(id) else {
            old?.setVolume(0, fadeDuration: duration)
            ambientPlayer = nil
            return
        }
        next.numberOfLoops = -1
        next.volume = 0
        next.prepareToPlay()
        next.play()
        next.setVolume(ambientGain, fadeDuration: duration)
        old?.setVolume(0, fadeDuration: duration)
        ambientPlayer = next
        // The old player is released once the fade completes; keeping a short
        // retain avoids an abrupt cut. It stops itself when deallocated.
        if let old { retireFadingPlayer(old, after: duration) }
    }

    public func startAmbientLayer(_ id: SoundID, volume: Float) {
        ambientLayerPlayer?.stop()
        ambientLayerVolume = volume
        guard let player = makePlayer(id) else { ambientLayerPlayer = nil; return }
        player.numberOfLoops = -1
        player.volume = muted ? 0 : volume * masterVolume
        player.prepareToPlay()
        player.play()
        ambientLayerPlayer = player
    }

    public func setAmbientScale(_ scale: Float, duration: TimeInterval) {
        ambientScale = max(0, min(1, scale))
        ambientPlayer?.setVolume(ambientGain, fadeDuration: duration)
    }

    // MARK: - One-shots

    public func play(_ id: SoundID, category: SoundCategory) {
        play(id, category: category, completion: nil)
    }

    public func play(_ id: SoundID, category: SoundCategory, completion: (() -> Void)?) {
        // Spoken cues are never gated by VoiceOver (D-028): they always play.
        guard !muted, let player = makePlayer(id) else {
            // Missing file or muted: nothing to play, but advance any sequence.
            if let completion { DispatchQueue.main.async(execute: completion) }
            return
        }
        player.volume = gain(for: category)
        if completion != nil {
            player.delegate = self
            let key = ObjectIdentifier(player)
            completions[key] = completion
            completionPlayers[key] = player
        }
        player.prepareToPlay()
        player.play()
        oneShots.append(player)
        if oneShots.count > maxOverlap { oneShots.removeFirst() }
        if category.isSpoken {
            spokenPlayers.append(player)
            if spokenPlayers.count > 4 { spokenPlayers.removeFirst() }
        }
    }

    public func spokenAudioRemaining() -> TimeInterval {
        spokenPlayers.reduce(0) { longest, player in
            guard player.isPlaying else { return longest }
            return max(longest, player.duration - player.currentTime)
        }
    }

    public func stopAll() {
        ambientPlayer?.stop(); ambientPlayer = nil
        ambientLayerPlayer?.stop(); ambientLayerPlayer = nil
        currentAmbientID = nil
        oneShots.forEach { $0.stop() }
        oneShots.removeAll()
        spokenPlayers.removeAll()
        // Fire any pending completions so callers waiting on a sequence unblock.
        let pending = completions
        completions.removeAll()
        completionPlayers.removeAll()
        for (_, done) in pending { DispatchQueue.main.async(execute: done) }
    }

    public func setMasterVolume(_ volume: Float) {
        masterVolume = min(1, max(0, volume))
        ambientPlayer?.volume = ambientGain
    }

    public func setMuted(_ muted: Bool) {
        self.muted = muted
        ambientPlayer?.volume = ambientGain
        ambientLayerPlayer?.volume = muted ? 0 : ambientLayerVolume * masterVolume
    }

    // MARK: - AVAudioPlayerDelegate

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let key = ObjectIdentifier(player)
        let done = completions.removeValue(forKey: key)
        completionPlayers.removeValue(forKey: key)
        done?()
    }

    // MARK: - Diagnostics

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

    private var ambientGain: Float {
        muted ? 0 : SoundCategory.ambient.defaultVolume * masterVolume * ambientScale
    }

    /// Keeps a fading-out player alive briefly, then stops it. No timers are
    /// committed to state; a detached task suffices and is harmless if cancelled.
    private func retireFadingPlayer(_ player: AVAudioPlayer, after duration: TimeInterval) {
        Task { [weak player] in
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.1) * 1_000_000_000))
            player?.stop()
        }
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
