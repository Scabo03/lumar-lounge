import Foundation
@testable import UI
import Audio

/// An `AudioServicing` that records, in order, every sound it is asked to play —
/// used to characterise the audio layer and to print a sound log for a hand.
/// The completion variant fires immediately so a `SpeechConductor` sequence
/// advances synchronously in tests.
final class RecordingAudioService: AudioServicing {
    struct Entry: Equatable { let id: SoundID; let category: SoundCategory }

    private(set) var log: [Entry] = []
    private(set) var ambient: [SoundID] = []
    private(set) var stoppedAll = 0
    /// Raw values of sounds to report as NOT in the bundle (for the fallback test).
    var missing: Set<String> = []

    func isAvailable(_ id: SoundID) -> Bool { !missing.contains(id.rawValue) }
    func startAmbient(_ id: SoundID) { ambient.append(id) }
    func play(_ id: SoundID, category: SoundCategory) { log.append(Entry(id: id, category: category)) }
    func play(_ id: SoundID, category: SoundCategory, completion: (() -> Void)?) {
        log.append(Entry(id: id, category: category)); completion?()
    }
    func stopAll() { stoppedAll += 1 }
    func setMasterVolume(_ volume: Float) {}
    func setMuted(_ muted: Bool) {}
    func spokenAudioRemaining() -> TimeInterval { 0 }
    func crossfadeAmbient(to id: SoundID, duration: TimeInterval) { ambient.append(id) }
    func startAmbientLayer(_ id: SoundID, volume: Float) {}
    func setAmbientScale(_ scale: Float, duration: TimeInterval) {}

    /// Convenience view used by several tests.
    var played: [(id: SoundID, category: SoundCategory)] { log.map { ($0.id, $0.category) } }
    var croupierPlays: [SoundID] { log.filter { $0.category == .croupier }.map(\.id) }
    var botVoicePlays: [SoundID] { log.filter { $0.category == .botVoice }.map(\.id) }
}
