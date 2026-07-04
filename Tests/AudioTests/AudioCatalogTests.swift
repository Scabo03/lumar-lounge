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

    // MARK: - VoiceOver coordination policy (D-024)

    func testSpokenCategoriesAreSilencedUnderVoiceOver() {
        XCTAssertFalse(AudioPolicy.shouldPlay(.croupier, voiceOverRunning: true))
        XCTAssertFalse(AudioPolicy.shouldPlay(.botVoice, voiceOverRunning: true))
        // Non-spoken sounds keep playing under VoiceOver.
        XCTAssertTrue(AudioPolicy.shouldPlay(.ambient, voiceOverRunning: true))
        XCTAssertTrue(AudioPolicy.shouldPlay(.table, voiceOverRunning: true))
        XCTAssertTrue(AudioPolicy.shouldPlay(.effect, voiceOverRunning: true))
        XCTAssertTrue(AudioPolicy.shouldPlay(.ui, voiceOverRunning: true))
    }

    func testEverythingPlaysWhenVoiceOverIsOff() {
        for category in SoundCategory.allCases {
            XCTAssertTrue(AudioPolicy.shouldPlay(category, voiceOverRunning: false))
        }
    }

    func testSpokenCategorisation() {
        XCTAssertTrue(SoundCategory.croupier.isSpoken)
        XCTAssertTrue(SoundCategory.botVoice.isSpoken)
        XCTAssertFalse(SoundCategory.ambient.isSpoken)
        XCTAssertFalse(SoundCategory.effect.isSpoken)
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
        engine.startAmbient(SoundCatalog.ambientLounge)
        engine.play(SoundCatalog.chipsBet, category: .table)
        engine.setMasterVolume(0.5)
        engine.setMuted(true)
        engine.stopAll()
    }
}
