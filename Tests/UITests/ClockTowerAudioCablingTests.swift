import XCTest
@testable import UI
@testable import GameWorld
import Audio

/// The ClockTower audio cabling (D-080): the files the user produced are present in
/// `Resources/Audio` under the names the code expects, the deliberately-excluded cues fall
/// back (synthesis or silence), and no ambiguous file was cabled. This FAILS if a cabled
/// slot points to a file that isn't in the bundle folder.
final class ClockTowerAudioCablingTests: XCTestCase {

    /// The real `Resources/Audio` directory on disk (like `PhoneticsTests` reads it.lproj).
    private func audioDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Audio")
    }

    private func exists(_ id: SoundID) -> Bool {
        FileManager.default.fileExists(atPath: audioDir().appendingPathComponent("\(id.rawValue).mp3").path)
    }
    private func existsRaw(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: audioDir().appendingPathComponent("\(name).mp3").path)
    }

    // MARK: - Delivered & cabled → the file must exist

    func testCabledClockTowerVoicesArePresent() {
        // ClockTower ambient (both letti) + clock layer.
        let ambient: [SoundID] = [
            SoundCatalog.ambClocktowerCalm1, SoundCatalog.ambClocktowerCalm2, SoundCatalog.ambClocktowerThinking,
            SoundCatalog.ambClocktowerClock,
            SoundCatalog.ambClocktowerMachiavelli1, SoundCatalog.ambClocktowerMachiavelli2,
            SoundCatalog.ambClocktowerMachiavelliThinking,
        ]
        // Machiavelli arbiter (delivered subset) + tower croupier wired to Stud (delivered).
        let voices: [SoundID] = [
            SoundCatalog.voClockYourTurn, SoundCatalog.voClockMeld, SoundCatalog.voClockMatchEnd,
            SoundCatalog.voTowerNewHand, SoundCatalog.voTowerShowdown, SoundCatalog.voTowerPotAwarded,
            SoundCatalog.voTowerSplitPot, SoundCatalog.voTowerGameEnd,
        ]
        for id in ambient + voices {
            XCTAssertTrue(exists(id), "cabled ClockTower slot \(id.rawValue) has no file in Resources/Audio")
        }
    }

    // MARK: - Deliberately NOT delivered → the fallback path (silence / synthesis) is used

    func testExcludedCuesAreAbsentSoTheyFallBack() {
        // Lower ClockTower verbosity (D-080): these were intentionally not produced. They must
        // be ABSENT so the fallback (synthesis for the turn/prize, silence for the rest) runs.
        for id in [SoundCatalog.voTowerYourTurn, SoundCatalog.voTowerHousePrize,
                   SoundCatalog.voClockHandStart, SoundCatalog.voClockDrew, SoundCatalog.voClockPassed] {
            XCTAssertFalse(exists(id), "\(id.rawValue) should be absent (fallback), but a file was cabled")
        }
        // The bot colour voices (vob_clock_*) were not produced → silence fallback (D-066).
        for id in [SoundCatalog.vobClockStudentEager, SoundCatalog.vobClockProfessorMasterstroke] {
            XCTAssertFalse(exists(id), "\(id.rawValue) should be absent (silence fallback)")
        }
    }

    func testAmbiguousFilesWereNotCabled() {
        // `opponent_shift` / `player_shift` had no clear event mapping → left out, not guessed.
        XCTAssertFalse(existsRaw("vo_it_clock_opponent_shift"), "an ambiguous file was cabled without a mapping")
        XCTAssertFalse(existsRaw("vo_it_clock_player_shift"), "an ambiguous file was cabled without a mapping")
    }

    // MARK: - Reserved future-Texas croupier files are bundled but unwired

    func testReservedTowerFilesArePresentButUncatalogued() {
        // The user produced a full generic-poker set; these map to blinds/community/button —
        // absent from Stud. They are bundled (ready for a future ClockTower Texas table) but
        // not referenced by any speech map, so they are not in the catalog.
        let reserved = ["vo_it_tower_big_blind", "vo_it_tower_small_blind", "vo_it_tower_flop",
                        "vo_it_tower_turn", "vo_it_tower_river", "vo_it_tower_role_button", "vo_it_tower_stakes_rise"]
        for name in reserved { XCTAssertTrue(existsRaw(name), "\(name) should be bundled for future use") }
        let catalogued = Set(SoundCatalog.all.map { $0.id.rawValue })
        for name in reserved { XCTAssertFalse(catalogued.contains(name), "\(name) is reserved/unwired — not catalogued yet") }
    }
}
