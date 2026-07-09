// TableRules.swift
// =====================================================================
// A table's configuration (D-035/D-037): blinds, buy-in, the bots' personalities,
// and whether it runs the decisive-hand boost. Two styles at the Riverwood Casino:
// Classic (the M1 experience, unchanged) and Fast (more aggressive bots + boost).
//
// The bots' personalities for the Fast table are defined HERE, in GameWorld — the
// engine only receives personalities as input, it never decides them (CONVENTIONS).
// The blinds/buy-in are fed to the existing SessionDriver config entry points; the
// driver itself isn't changed structurally.

import Foundation
import GameEngine

public enum TableFormat: String, Equatable, Sendable, CaseIterable {
    case classic, fast
}

public struct TableRules: Equatable, Sendable {
    public let style: TableFormat
    public let smallBlind: Int
    public let bigBlind: Int
    public let buyIn: Int
    public let personalities: [Personality]   // the three bots
    public let decisiveHandBoost: Bool

    public init(style: TableFormat, smallBlind: Int, bigBlind: Int, buyIn: Int,
                personalities: [Personality], decisiveHandBoost: Bool) {
        self.style = style
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.buyIn = buyIn
        self.personalities = personalities
        self.decisiveHandBoost = decisiveHandBoost
    }

    /// The M1 table, unchanged: the starting roster, 10/20, 1000 buy-in.
    public static let classic = TableRules(
        style: .classic, smallBlind: 10, bigBlind: 20, buyIn: 1000,
        personalities: WorldPersonalities.classic, decisiveHandBoost: false)

    /// The Fast table: visibly more aggressive bots and the decisive-hand boost.
    public static let fast = TableRules(
        style: .fast, smallBlind: 10, bigBlind: 20, buyIn: 1000,
        personalities: WorldPersonalities.fast, decisiveHandBoost: true)
}

/// The bots' personalities per table style (defined in GameWorld, not GameEngine).
public enum WorldPersonalities {

    public static let classic: [Personality] = [.eagerNovice, .conservativeRock, .hotAggressor]

    /// Fast-table variants: aggression, bluff and risk UP, tightness DOWN — visibly
    /// looser and pushier, but rationality kept moderate so they aren't just stupid.
    /// They are also MORE STUBBORN and showdown-bound than at the Classic table
    /// (higher pressureResistance) and play even more junk (lower trashFoldTendency),
    /// to keep the Fast table's dramatic-clash character (D-037/D-048). Slots map to
    /// the novice / rock / aggressor characters in order.
    public static let fast: [Personality] = [
        Personality(name: "Riverwood Gambler",   // novice slot
                    tightness: 0.15, aggression: 0.75, bluffFrequency: 0.55, riskTolerance: 0.70,
                    positionAwareness: 0.20, rationality: 0.45, tiltReactivity: 0.75,
                    pressureResistance: 0.60, trashFoldTendency: 0.15),
        Personality(name: "Loose Rock",          // rock slot
                    tightness: 0.50, aggression: 0.55, bluffFrequency: 0.30, riskTolerance: 0.55,
                    positionAwareness: 0.65, rationality: 0.80, tiltReactivity: 0.30,
                    pressureResistance: 0.70, trashFoldTendency: 0.75),
        Personality(name: "Wild Aggressor",      // aggressor slot
                    tightness: 0.20, aggression: 0.97, bluffFrequency: 0.72, riskTolerance: 0.92,
                    positionAwareness: 0.20, rationality: 0.50, tiltReactivity: 0.60,
                    pressureResistance: 0.90, trashFoldTendency: 0.05),
    ]
}

/// The decisive-hand boost (D-037): after `threshold` consecutive hands in which
/// nobody folded pre-flop, the NEXT hand is "decisive" (its blinds are doubled and
/// the croupier announces it). A transparent, narrative mechanic — testable in
/// isolation, living in GameWorld, invisible to the engine.
public final class DecisiveHandBoost {

    public let threshold: Int
    public private(set) var streak = 0

    public init(threshold: Int = 3) { self.threshold = threshold }

    /// Whether the upcoming hand should be decisive.
    public var isNextHandDecisive: Bool { streak >= threshold }

    /// Records a finished ordinary hand: a pre-flop fold breaks the streak.
    public func recordHand(anyFoldPreflop: Bool) {
        streak = anyFoldPreflop ? 0 : streak + 1
    }

    /// Called once a decisive hand has been dealt, so the counter restarts.
    public func consumeDecisiveHand() { streak = 0 }
}
