// ClockAmbient.swift
// =====================================================================
// Two small PURE helpers for the ClockTower's ambient behaviour (D-080), kept out of the
// audio directors so they are unit-testable without any audio:
//
//   • `ClockAmbientRotation` — which calm movement plays, FAVOURING calm_02 over calm_01
//     in the rotation (a user mixing choice).
//   • `ClockChime` — the DOSING schedule for the tower clock: brief audible appearances of
//     a few seconds separated by LONG gaps (dozens of seconds), so the clock reads as the
//     tower's occasional presence and never a constant tick (which would be torture in a
//     long game).
//
// UI only. Deterministic given the RNG.

import Foundation
import GameEngine

/// Which calm movement the ClockTower plays, biased toward calm_02 (D-080).
enum ClockAmbientRotation {
    /// Whether movement `index` should use the SECOND calm bed (calm_02). calm_01 appears
    /// only every third movement, so calm_02 carries ~2/3 of the rotation — the user's
    /// "favour calm_02" mixing choice, while calm_01 still returns for variety.
    static func usesSecondMovement(_ index: Int) -> Bool {
        index % 3 != 0
    }
}

/// The dosing schedule of the ClockTower clock (D-080): each cycle is a long silent GAP
/// followed by a short audible burst.
struct ClockChime {
    /// The silent gap between clock appearances (seconds): dozens of seconds.
    static let gapRange: ClosedRange<Double> = 30...70
    /// The audible duration of one clock appearance (seconds): a few to a few tens.
    static let onRange: ClosedRange<Double> = 4...12

    /// The next (gap, on) pair, drawn deterministically from `rng`.
    static func next(using rng: inout SeededGenerator) -> (gap: Double, on: Double) {
        (gap: sample(gapRange, &rng), on: sample(onRange, &rng))
    }

    private static func sample(_ range: ClosedRange<Double>, _ rng: inout SeededGenerator) -> Double {
        let u = Double(rng.next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
        return range.lowerBound + u * (range.upperBound - range.lowerBound)
    }
}
