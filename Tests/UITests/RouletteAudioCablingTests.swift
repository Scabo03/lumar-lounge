// RouletteAudioCablingTests.swift
// =====================================================================
// D-104 — the real roulette mp3s and the chip-set files: every cabled slot must
// point to a file that actually exists in `Resources/Audio/` (a forgotten or
// mis-renamed file fails loudly, not silently), the ONE undelivered slot keeps
// its declared fallback, and the removed croupier voices must not linger in the
// catalog.

import XCTest
@testable import UI
import Audio

final class RouletteAudioCablingTests: XCTestCase {

    private func audioDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Audio")
    }
    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: audioDir().appendingPathComponent("\(name).mp3").path)
    }

    /// The mp3s delivered and cabled in D-104 (renamed to the catalog form).
    private let cabled: [SoundID] = [
        SoundCatalog.fxRouletteWheelSpin, SoundCatalog.fxRouletteBall,
        SoundCatalog.fxRouletteWin, SoundCatalog.fxRouletteLose,
        SoundCatalog.fxRouletteChipPlace, SoundCatalog.fxRouletteChipRemove,
        SoundCatalog.fxRoulettePresenceMurmur, SoundCatalog.fxRoulettePresenceChips,
        SoundCatalog.sfxChipsShifted1, SoundCatalog.sfxChipsShifted2,
        SoundCatalog.sfxChipsShifted3, SoundCatalog.sfxChipsShifted4,
    ]

    func testEveryCabledSlotHasItsFileOnDisk() {
        for id in cabled {
            XCTAssertTrue(exists(id.rawValue),
                          "cabled slot '\(id.rawValue)' has no mp3 in Resources/Audio — forgotten or mis-renamed?")
        }
    }

    /// `fx_roulette_win` is bundled as a byte-identical COPY of `tbl_chips_stack` —
    /// the poker call's chip sound, the user's explicit pick for the win sting
    /// (D-104): chips gathered, not a jingle. A dedicated win sound, if ever
    /// produced, just overwrites the file (this guard then fails on purpose so the
    /// provenance note in the catalog gets updated too).
    func testTheWinSlotIsTheCallChipSound() throws {
        let win = audioDir().appendingPathComponent("fx_roulette_win.mp3")
        let stack = audioDir().appendingPathComponent("tbl_chips_stack.mp3")
        XCTAssertEqual(try Data(contentsOf: win), try Data(contentsOf: stack),
                       "fx_roulette_win diverged from tbl_chips_stack: a dedicated win sound landed — update the provenance notes (SoundCatalog, Roulette_audio_catalog.md)")
    }

    /// The roulette croupier voices were REMOVED (D-104, user decision): the catalog
    /// must not declare them, and no file must pretend they exist.
    func testTheRemovedCroupierVoicesAreGoneFromTheCatalog() {
        let names = SoundCatalog.all.map { $0.id.rawValue }
        XCTAssertFalse(names.contains { $0.contains("roulette_rien_ne_va_plus") },
                       "the removed roulette croupier slots must not return to the catalog")
        XCTAssertFalse(exists("vo_it_roulette_rien_ne_va_plus"))
        XCTAssertFalse(exists("vo_it_sky_roulette_rien_ne_va_plus"))
    }

    /// The four chip-set files are in the shared TABLE pool with the two historical
    /// movement sounds (the mechanism itself is covered in `TableChipSetTests`).
    func testTheChipSetFilesAreCatalogued() {
        let catalogued = Set(SoundCatalog.all.map { $0.id })
        for id in TableChipSet.pool {
            XCTAssertTrue(catalogued.contains(id), "\(id.rawValue) missing from SoundCatalog.all")
        }
    }
}
