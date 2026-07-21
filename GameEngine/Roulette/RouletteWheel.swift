// RouletteWheel.swift
// =====================================================================
// The spinning wheel (D-101): a seeded source of pockets 0…36.
//
// Determinism given a seed is the whole of it — the same seed produces the same
// sequence of pockets across a session, so tests are reproducible and, in
// production, a fresh system seed makes every session and every spin different
// (D-047). The wheel carries its own generator, exactly as the shoe does.

import Foundation

public struct RouletteWheel: Sendable {

    private var generator: SeededGenerator

    public init(seed: UInt64) {
        self.generator = SeededGenerator(seed: seed)
    }

    /// Spins once and returns the winning pocket, 0…36, uniformly.
    public mutating func spin() -> Int {
        Int.random(in: 0...36, using: &generator)
    }
}
