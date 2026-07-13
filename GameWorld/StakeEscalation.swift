// StakeEscalation.swift
// =====================================================================
// A reusable, table-configurable SESSION-ACCELERATION mechanic (D-064): as a
// session runs long, the stakes ratchet up on a schedule — like tournament blind
// levels — so short-stacked all-ins arrive and the session ends. It is a plain,
// game-agnostic value: it computes a stake multiplier from the number of PLAYED
// hands. The driver decides what to multiply (blinds for Omaha/Texas; ante/bets for
// a limit game). It lives in GameWorld, not in any one engine, precisely so it is a
// configurable table parameter reusable by every game's session driver, present and
// future — Omaha uses it now; Texas Fast and Draw Whiskey keep their own existing
// mechanics for now and could adopt this later without breaking (§ CONVENTIONS).
//
// ACCESSIBILITY RULE (permanent, CONVENTIONS §4): the trigger is the count of
// PLAYED HANDS, NEVER elapsed time. A blind player takes more real time for the same
// amount of play; any minutes-based acceleration would punish them for their reading
// speed rather than their choices at the table. "Nobody loses anything", applied to
// time. Every acceleration mechanic in the project MUST key on hands played.
//
// Foundation only.

import Foundation

/// Escalates the stakes every `interval` PLAYED hands by a fixed `factor` (a
/// permanent ratchet, like tournament levels). Deterministic — a fixed schedule, no
/// RNG. `interval == 0` (the default `.none`) disables it.
public struct StakeEscalation: Equatable, Sendable {
    /// Played hands between level-ups. 0 disables escalation.
    public let interval: Int
    /// Stake multiplier applied at each level (must be ≥ 1 to escalate).
    public let factor: Double

    public init(interval: Int, factor: Double) {
        self.interval = max(0, interval)
        self.factor = max(1.0, factor)
    }

    /// Escalation disabled — the stakes never change.
    public static let none = StakeEscalation(interval: 0, factor: 1)

    /// The current level (number of escalations) after `playedHands` completed hands.
    public func level(afterPlayedHands playedHands: Int) -> Int {
        guard interval > 0, factor > 1, playedHands > 0 else { return 0 }
        return playedHands / interval
    }

    /// The cumulative stake multiplier after `playedHands` completed hands:
    /// `factor ^ level`. 1.0 when disabled or before the first level-up.
    public func multiplier(afterPlayedHands playedHands: Int) -> Double {
        let l = level(afterPlayedHands: playedHands)
        return l == 0 ? 1.0 : pow(factor, Double(l))
    }

    /// The escalated (small, big) blinds after `playedHands`, keeping `small ≤ big`
    /// and both ≥ 1 after rounding.
    public func blinds(baseSmall: Int, baseBig: Int, afterPlayedHands playedHands: Int) -> (small: Int, big: Int) {
        let m = multiplier(afterPlayedHands: playedHands)
        let small = max(1, Int((Double(baseSmall) * m).rounded()))
        let big = max(small, Int((Double(baseBig) * m).rounded()))
        return (small, big)
    }
}
