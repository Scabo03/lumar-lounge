import XCTest
@testable import Audio
import AVFoundation

final class AudioCatalogTests: XCTestCase {

    // MARK: - Catalog well-formedness

    func testCatalogIsNonEmptyAndUnique() {
        XCTAssertFalse(SoundCatalog.all.isEmpty)
        let names = SoundCatalog.all.map { $0.id.rawValue }
        XCTAssertEqual(Set(names).count, names.count, "Duplicate sound file names in the catalog")
    }

    func testEveryCatalogEntryHasASensibleVolume() {
        for entry in SoundCatalog.all {
            let v = entry.category.defaultVolume
            XCTAssertGreaterThan(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }

    // MARK: - Audio-VoiceOver coordination (D-028)

    func testSpokenCategorisation() {
        XCTAssertTrue(SoundCategory.croupier.isSpoken)
        XCTAssertTrue(SoundCategory.botVoice.isSpoken)
        XCTAssertFalse(SoundCategory.ambient.isSpoken)
        XCTAssertFalse(SoundCategory.effect.isSpoken)
    }

    /// Strategy C (D-028): spoken cues are no longer gated by VoiceOver — the old
    /// silencing policy is gone, so there is nothing to silence them. The engine
    /// only reports how much spoken audio is still playing, for coordination. A
    /// fresh engine reports none, and driving it (files missing in the test bundle,
    /// so no player is created) never invents phantom remaining time.
    func testEngineReportsNoSpokenAudioWhenIdle() {
        let engine = AudioEngine(configureSession: false)
        XCTAssertEqual(engine.spokenAudioRemaining(), 0)
        engine.play(SoundCatalog.voHandStart, category: .croupier)
        engine.play(SoundCatalog.vobNoviceExcited, category: .botVoice)
        XCTAssertEqual(engine.spokenAudioRemaining(), 0)
        engine.stopAll()
        XCTAssertEqual(engine.spokenAudioRemaining(), 0)
    }

    // MARK: - Engine: bundled files are loadable; missing ones degrade gracefully

    func testEnginePreflightReportsMissingWithoutCrashing() {
        // In the test bundle none of the catalog mp3s are present, so all are
        // reported missing — and the engine is still fully usable (no crash).
        let engine = AudioEngine(configureSession: false)
        let missing = Set(engine.missingSounds().map { $0.rawValue })
        // For every catalog sound: if present in the bundle it must load;
        // otherwise it is (correctly) reported missing.
        for entry in SoundCatalog.all {
            if let url = Bundle.main.url(forResource: entry.id.rawValue, withExtension: "mp3") {
                XCTAssertNoThrow(try AVAudioPlayer(contentsOf: url), "\(entry.id.rawValue) is present but not loadable")
                XCTAssertFalse(missing.contains(entry.id.rawValue))
            } else {
                XCTAssertTrue(missing.contains(entry.id.rawValue))
            }
        }
        // Driving the engine with missing files must be safe.
        engine.startAmbient(SoundCatalog.ambLoungeCalm1)
        engine.play(SoundCatalog.tblChipsStack, category: .table)
        engine.setMasterVolume(0.5)
        engine.setMuted(true)
        engine.stopAll()
    }
}
