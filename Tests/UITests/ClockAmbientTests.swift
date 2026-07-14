import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine
import Audio

/// The ClockTower ambient MIXING and clock DOSING (D-080): quieter beds per table,
/// calm_02-favoured rotation, and the clock as an occasional presence — never a constant
/// tick. Riverwood/Skypool must stay identical.
final class ClockAmbientTests: XCTestCase {

    // MARK: - Pure helpers

    func testRotationFavoursCalm02() {
        // calm_01 appears only every third movement; calm_02 carries the rest (~2/3).
        let uses02 = (0..<12).map { ClockAmbientRotation.usesSecondMovement($0) }
        XCTAssertEqual(uses02, [false, true, true, false, true, true, false, true, true, false, true, true])
        let second = uses02.filter { $0 }.count
        XCTAssertGreaterThan(second, uses02.count - second, "calm_02 is favoured over calm_01")
    }

    func testClockChimeIsOccasionalNeverContinuous() {
        var rng = SeededGenerator(seed: 2026)
        for _ in 0..<500 {
            let (gap, on) = ClockChime.next(using: &rng)
            XCTAssertTrue(ClockChime.gapRange.contains(gap), "gap is dozens of seconds")
            XCTAssertTrue(ClockChime.onRange.contains(on), "on is a few to a few tens of seconds")
            // The gap always dwarfs the audible burst — the clock is never a constant tick.
            XCTAssertGreaterThan(gap, on, "the silent gap always exceeds the audible burst")
        }
        // The minimum gap (30s) is far larger than the maximum burst (12s): occasional.
        XCTAssertGreaterThan(ClockChime.gapRange.lowerBound, ClockChime.onRange.upperBound)
    }

    // MARK: - Mixing levels are DATA on the beds (D-080)

    func testClockTowerBedsAreMixedQuieterAndDoseTheClock() {
        XCTAssertEqual(AmbientBeds.clocktower.bedVolume, 0.80, "poker ~20% below the other casinos")
        XCTAssertEqual(AmbientBeds.clocktowerMachiavelli.bedVolume, 0.65, "Machiavelli ~35% below")
        XCTAssertTrue(AmbientBeds.clocktower.layerIsOccasional, "the ClockTower clock is dosed")
        XCTAssertTrue(AmbientBeds.clocktowerMachiavelli.layerIsOccasional)
    }

    func testRiverwoodAndSkypoolBedsAreUnchanged() {
        // Full-level, continuous layer — no ClockTower mixing/dosing leaks into them.
        for beds in [AmbientBeds.riverwood, AmbientBeds.skypool] {
            XCTAssertEqual(beds.bedVolume, 1.0, "other casinos are at full mixing level")
            XCTAssertFalse(beds.layerIsOccasional, "other casinos keep a continuous layer")
        }
    }

    // MARK: - The Stud director applies the mixing & starts the clock silent

    @MainActor
    func testStudDirectorMixesQuieterAndStartsTheClockSilent() {
        let audio = RecordingAudioService()
        let dir = StudAudioDirector(audio: audio, heroSeatID: 0, fastMode: true, seed: 1, ambient: .clocktower)
        dir.handle(.sessionBegan(seats: [StudSeatSnapshot(seatID: 0, position: 0, chips: 3000)],
                                 ante: 25, bringIn: 25, bet: 50))
        // The main bed is scaled to the ClockTower mixing level (0.80), not 1.0.
        XCTAssertEqual(audio.ambientScales.first, 0.80)
        // The clock layer is started SILENT (volume 0) — the dosing task fades it in later.
        XCTAssertEqual(audio.layerStarts.first?.volume, 0, "the dosed clock starts silent")

        // The showdown hush is relative to the base level (0.80 × 0.35), not an absolute 0.35.
        dir.handle(.handShown(seatID: 0, cards: [], category: .pair, bestFive: []))
        XCTAssertEqual(audio.ambientScales.last!, Float(0.80 * 0.35), accuracy: 0.001)
    }

    @MainActor
    func testContinuousLayerCasinoStartsTheLayerAudible() {
        // A director given continuous-layer beds (Riverwood) starts the layer at its volume.
        let audio = RecordingAudioService()
        let dir = StudAudioDirector(audio: audio, heroSeatID: 0, fastMode: true, seed: 1, ambient: .riverwood)
        dir.handle(.sessionBegan(seats: [], ante: 25, bringIn: 25, bet: 50))
        XCTAssertEqual(audio.layerStarts.first?.volume, AmbientBeds.riverwood.layerVolume,
                       "a continuous layer starts audible, not dosed")
        XCTAssertEqual(audio.ambientScales.first, 1.0, "full-level casinos are unchanged")
    }

    @MainActor
    func testStudDirectorFavoursCalm02AcrossHands() {
        let audio = RecordingAudioService()
        let dir = StudAudioDirector(audio: audio, heroSeatID: 0, fastMode: true, seed: 1, ambient: .clocktower)
        dir.handle(.sessionBegan(seats: [], ante: 25, bringIn: 25, bet: 50))
        // Movements 1,2 → calm_02; movement 3 → calm_01. Fallbacks apply (no files), so we
        // check against the resolved beds.
        var seen: [SoundID] = []
        for _ in 0..<3 {
            dir.handle(.handBegan(handNumber: 0, ante: 25, bringIn: 25, bet: 50, seats: []))
            seen.append(audio.ambient.last!)
        }
        // Two of the three crossfades used the calm_02 bed (the recorder reports all files
        // available, so `bed(...)` resolves to the preferred id).
        let calm2 = AmbientBeds.clocktower.calm2
        XCTAssertEqual(seen.filter { $0 == calm2 }.count, 2, "calm_02 is favoured in the rotation")
    }
}
