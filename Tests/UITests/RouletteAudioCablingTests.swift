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
        SoundCatalog.fxRouletteLose,
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

    /// `fx_roulette_win` was NOT produced: the view model falls back to the generic
    /// win cue. If the file ever lands, this fails on purpose — drop the fallback
    /// check in `sting(for:)` deliberately, not by accident.
    func testTheUndeliveredWinSlotStaysEmpty() {
        XCTAssertFalse(exists(SoundCatalog.fxRouletteWin.rawValue),
                       "fx_roulette_win landed: revisit the sting fallback in RouletteTableViewModel")
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
