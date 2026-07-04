// RaiseCurve.swift
// =====================================================================
// The progressive step curve of the Raise box (D-020): fine control near the
// minimum, fast acceleration towards the stack.
//
//   clicks 1–3 : +10 each
//   clicks 4–6 : +25 each
//   clicks 7–8 : +50 each
//   clicks 9–10: +100 each
//   clicks 11+ : +250 each
//
// Pure and self-contained, so it is unit-testable without any UI. The Raise box
// stores a click count as its source of truth; the shown value is derived and
// clamped to the legal [min, max] window.

import Foundation

public enum RaiseCurve {

    /// The increment applied to go from click `k` to click `k + 1`.
    public static func increment(atClick k: Int) -> Int {
        switch k {
        case 0, 1, 2: return 10
        case 3, 4, 5: return 25
        case 6, 7: return 50
        case 8, 9: return 100
        default: return 250
        }
    }

    /// The raise value after `clicks` presses of "+", starting from `min`,
    /// clamped so it never exceeds `max`.
    public static func value(clicks: Int, min: Int, max: Int) -> Int {
        guard clicks > 0 else { return Swift.min(min, max) }
        var value = min
        var k = 0
        while k < clicks {
            value += increment(atClick: k)
            if value >= max { return max }
            k += 1
        }
        return Swift.min(value, max)
    }

    /// The number of clicks needed to first reach `max` from `min` — the click
    /// count the all-in shortcut jumps to (so "−" from all-in steps one down).
    public static func clicksToMax(min: Int, max: Int) -> Int {
        guard max > min else { return 0 }
        var value = min
        var k = 0
        while value < max {
            value += increment(atClick: k)
            k += 1
        }
        return k
    }
}

/// The Raise box's state: a click count over a legal [min, max] window, plus
/// whether the confirmed action is a bet (no prior bet) or a raise.
public struct RaiseBoxState: Equatable, Sendable {
    public var clicks: Int
    public let minTo: Int
    public let maxTo: Int
    public let isBet: Bool

    public var value: Int { RaiseCurve.value(clicks: clicks, min: minTo, max: maxTo) }
    public var isAtMax: Bool { value >= maxTo }
    public var isAtMin: Bool { clicks == 0 }

    public init(minTo: Int, maxTo: Int, isBet: Bool) {
        self.minTo = minTo
        self.maxTo = maxTo
        self.isBet = isBet
        self.clicks = 0
    }

    /// One step up the curve (never past all-in).
    public mutating func increase() {
        guard !isAtMax else { return }
        clicks = Swift.min(clicks + 1, RaiseCurve.clicksToMax(min: minTo, max: maxTo))
    }

    /// One step down the curve (never below the minimum).
    public mutating func decrease() {
        clicks = Swift.max(clicks - 1, 0)
    }

    /// Jump straight to all-in.
    public mutating func toMax() {
        clicks = RaiseCurve.clicksToMax(min: minTo, max: maxTo)
    }
}
