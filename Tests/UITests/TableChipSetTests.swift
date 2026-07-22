// TableChipSetTests.swift
// =====================================================================
// D-104 — the casino's chip sets: a session picks one or two chip-movement
// sounds from the pool and keeps them; the next session picks others.

import XCTest
@testable import UI
import Audio

final class TableChipSetTests: XCTestCase {

    // MARK: - The pool and the identity

    func testThePoolMixesTheHistoricalSoundsWithTheFourNewSets() {
        XCTAssertEqual(TableChipSet.pool.count, 6)
        XCTAssertTrue(TableChipSet.pool.contains(SoundCatalog.tblChipsSingle))
        XCTAssertTrue(TableChipSet.pool.contains(SoundCatalog.tblChipsStack))
        for id in [SoundCatalog.sfxChipsShifted1, SoundCatalog.sfxChipsShifted2,
                   SoundCatalog.sfxChipsShifted3, SoundCatalog.sfxChipsShifted4] {
            XCTAssertTrue(TableChipSet.pool.contains(id))
        }
    }

    func testTheIdentitySetIsThePreD104Sound() {
        XCTAssertEqual(TableChipSet.identity.light, SoundCatalog.tblChipsSingle)
        XCTAssertEqual(TableChipSet.identity.heavy, SoundCatalog.tblChipsStack)
    }

    // MARK: - Selection: deterministic, one or two, from the pool

    func testSelectionIsDeterministicGivenASeed() {
        for seed: UInt64 in [1, 7, 42, 999] {
            XCTAssertEqual(TableChipSet.selection(seed: seed), TableChipSet.selection(seed: seed))
        }
    }

    func testSelectionPicksOneOrTwoSoundsAndBothOccur() {
        var sawOne = false, sawTwo = false
        for seed: UInt64 in 1...200 {
            let set = TableChipSet.selection(seed: seed)
            XCTAssertTrue(TableChipSet.pool.contains(set.light))
            XCTAssertTrue(TableChipSet.pool.contains(set.heavy))
            if set.light == set.heavy { sawOne = true } else { sawTwo = true }
        }
        XCTAssertTrue(sawOne, "a session sometimes plays with a single set")
        XCTAssertTrue(sawTwo, "and sometimes with two")
    }

    func testEveryPoolMemberIsEventuallyChosen() {
        var chosen = Set<SoundID>()
        for seed: UInt64 in 1...300 {
            let set = TableChipSet.selection(seed: seed)
            chosen.insert(set.light); chosen.insert(set.heavy)
        }
        XCTAssertEqual(chosen, Set(TableChipSet.pool),
                       "over many sessions the whole cupboard gets used")
    }

    /// With two picks, the LIGHTER sound (earlier in the pool: the short tick before
    /// the long clatters) takes the light role — blinds tick, raises clatter, never
    /// the other way round.
    func testTwoPicksAreOrderedLightToHeavy() {
        for seed: UInt64 in 1...200 {
            let set = TableChipSet.selection(seed: seed)
            guard set.light != set.heavy else { continue }
            let li = TableChipSet.pool.firstIndex(of: set.light)!
            let hi = TableChipSet.pool.firstIndex(of: set.heavy)!
            XCTAssertLessThan(li, hi)
        }
    }

    // MARK: - Exclusion: the sessions right after sound different

    func testSelectionNeverPicksAnExcludedSound() {
        let excluded: Set<SoundID> = [SoundCatalog.tblChipsSingle, SoundCatalog.sfxChipsShifted2]
        for seed: UInt64 in 1...100 {
            let set = TableChipSet.selection(seed: seed, excluding: excluded)
            XCTAssertFalse(excluded.contains(set.light))
            XCTAssertFalse(excluded.contains(set.heavy))
        }
    }

    @MainActor
    func testConsecutiveSessionsNeverShareASound() {
        var previous = TableChipSet.forNewSession(seed: 1)
        for seed: UInt64 in 2...50 {
            let next = TableChipSet.forNewSession(seed: seed)
            XCTAssertFalse([next.light, next.heavy].contains(previous.light),
                           "the next session brings out another set")
            XCTAssertFalse([next.light, next.heavy].contains(previous.heavy))
            previous = next
        }
    }

    // MARK: - Resolution: only the two canonical movement IDs are substituted

    func testResolveSubstitutesOnlyTheGenericMovementSounds() {
        let set = TableChipSet(light: SoundCatalog.sfxChipsShifted1,
                               heavy: SoundCatalog.sfxChipsShifted3)
        XCTAssertEqual(set.resolve(SoundCatalog.tblChipsSingle), SoundCatalog.sfxChipsShifted1)
        XCTAssertEqual(set.resolve(SoundCatalog.tblChipsStack), SoundCatalog.sfxChipsShifted3)
        // The semantic moments and everything else pass through untouched.
        XCTAssertEqual(set.resolve(SoundCatalog.tblChipsBetLarge), SoundCatalog.tblChipsBetLarge)
        XCTAssertEqual(set.resolve(SoundCatalog.tblChipsPotCollect), SoundCatalog.tblChipsPotCollect)
        XCTAssertEqual(set.resolve(SoundCatalog.voYourTurn), SoundCatalog.voYourTurn)
    }
}
