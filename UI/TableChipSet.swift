// TableChipSet.swift
// =====================================================================
// D-104 — the casino owns SEVERAL physical chip sets, and a table session sounds
// like the one it plays with.
//
// The generic chip-MOVEMENT sounds (the ones heard on ordinary actions — blinds,
// calls, bets, raises) come from a POOL: the two historical files plus the four
// `sfx_chips_shifted_*` sets. Each session picks ONE or TWO from the pool and
// keeps them for its whole length; the next session picks others, so consecutive
// sessions never sound identical and the variety reads as "different chip sets",
// not randomness. The special-moment sounds (`tbl_chips_bet_large` for the all-in,
// `tbl_chips_pot_collect` for the pot sweep) are NOT substituted: they mark
// semantic moments, not the feel of a chip set.
//
// The pure `AudioScore`s keep emitting the canonical IDs (`tbl_chips_single` /
// `tbl_chips_stack`); the substitution happens at PLAY time in the directors via
// `resolve(_:)` — so score tests stay canonical and the mechanism lives in one
// place per director.

import Foundation
import Audio
import GameEngine

public struct TableChipSet: Equatable {

    /// Stands in for `tbl_chips_single` (the light movement: a blind, a call).
    public let light: SoundID
    /// Stands in for `tbl_chips_stack` (the heavier movement: a bet, a raise).
    public let heavy: SoundID

    public init(light: SoundID, heavy: SoundID) {
        self.light = light
        self.heavy = heavy
    }

    /// The whole cupboard: the two historical movement sounds mixed with the four
    /// new sets. Ordered lighter-to-heavier — the ordering decides which of two
    /// picks takes the light role, so a session that draws the short tick and a
    /// long clatter uses the tick for blinds, not the other way round.
    public static let pool: [SoundID] = [
        SoundCatalog.tblChipsSingle,
        SoundCatalog.tblChipsStack,
        SoundCatalog.sfxChipsShifted1,
        SoundCatalog.sfxChipsShifted2,
        SoundCatalog.sfxChipsShifted3,
        SoundCatalog.sfxChipsShifted4,
    ]

    /// The pre-D-104 sound: exactly the two historical files. The directors'
    /// default, so a test that builds one directly hears what it always heard.
    public static let identity = TableChipSet(light: SoundCatalog.tblChipsSingle,
                                              heavy: SoundCatalog.tblChipsStack)

    /// Pure, deterministic selection given a seed (D-047: seeded in tests, fed a
    /// fresh random seed per session in production). Picks one set (~40%) or two
    /// (~60%) from the pool minus `excluding`; with one pick both roles share it.
    public static func selection(seed: UInt64, excluding: Set<SoundID> = []) -> TableChipSet {
        var rng = SeededGenerator(seed: seed)
        var candidates = pool.filter { !excluding.contains($0) }
        if candidates.count < 2 { candidates = pool }

        let picksTwo = Double(rng.next() % 1000) / 1000.0 < 0.6
        let first = candidates.remove(at: Int(rng.next() % UInt64(candidates.count)))
        guard picksTwo else { return TableChipSet(light: first, heavy: first) }

        let second = candidates[Int(rng.next() % UInt64(candidates.count))]
        let ordered = [first, second].sorted {
            (pool.firstIndex(of: $0) ?? 0) < (pool.firstIndex(of: $1) ?? 0)
        }
        return TableChipSet(light: ordered[0], heavy: ordered[1])
    }

    /// The production entry point: remembers the previous session's picks and
    /// excludes them, so the sessions right after a game always sound different
    /// ("the casino brought out another set").
    @MainActor private static var previous: TableChipSet?
    @MainActor public static func forNewSession(seed: UInt64) -> TableChipSet {
        let excluded: Set<SoundID> = previous.map { [$0.light, $0.heavy] } ?? []
        let picked = selection(seed: seed, excluding: excluded)
        previous = picked
        return picked
    }

    /// The substitution the directors apply at play time: the two canonical
    /// movement IDs map to this session's set, everything else passes through.
    public func resolve(_ id: SoundID) -> SoundID {
        if id == SoundCatalog.tblChipsSingle { return light }
        if id == SoundCatalog.tblChipsStack { return heavy }
        return id
    }
}
