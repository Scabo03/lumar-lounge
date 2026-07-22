// TablePresence.swift
// =====================================================================
// The room's presence between rounds (D-090/D-104): occasional ambient one-shots
// that say "other patrons are here" without any NPC ever speaking. Category
// `.botVoice`, so a missing file falls back to SILENCE, never synthesis (D-066).
//
// Extracted from the blackjack director (whose algorithm it keeps verbatim) when
// roulette gained its own presence sounds: one mechanism, a repertoire per game.
// Deterministic given a seed (D-047); never repeats the previous cue back to back.

import Foundation
import Audio
import GameEngine

struct TablePresence {
    private var generator: SeededGenerator
    private let chance: Double
    private let repertoire: [SoundID]
    private var lastPlayed: SoundID?

    /// Shared across every casino, because no NPC ever speaks and therefore
    /// nothing here carries a place's identity (D-090).
    static let blackjack: [SoundID] = [
        SoundCatalog.fxBjPresenceChips,
        SoundCatalog.fxBjPresenceMurmur,
        SoundCatalog.fxBjPresenceCards
    ]
    static let roulette: [SoundID] = [
        SoundCatalog.fxRoulettePresenceMurmur,
        SoundCatalog.fxRoulettePresenceChips
    ]

    init(repertoire: [SoundID], seed: UInt64, chance: Double = 0.28) {
        self.repertoire = repertoire
        self.generator = SeededGenerator(seed: seed)
        self.chance = chance
    }

    /// The sound the room makes between one round and the next, if any.
    /// Never repeats the previous one back to back.
    mutating func next() -> SoundID? {
        let roll = Double(generator.next() % 1000) / 1000.0
        guard roll < chance else { return nil }

        var candidates = repertoire.filter { $0 != lastPlayed }
        if candidates.isEmpty { candidates = repertoire }
        let pick = candidates[Int(generator.next() % UInt64(candidates.count))]
        lastPlayed = pick
        return pick
    }
}
