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

    /// The M1 table: the starting roster, 20/40, 1000 buy-in. PACE (D-084) — the blinds
    /// were doubled from 10/20: a 1000 stack was 50 big blinds deep, so sessions dragged.
    /// Texas here is NO LIMIT, so bigger blinds shorten the session without changing the
    /// betting structure (there is no pot-size ceiling to inflate).
    public static let classic = TableRules(
        style: .classic, smallBlind: 20, bigBlind: 40, buyIn: 1000,
        personalities: WorldPersonalities.classic, decisiveHandBoost: false)

    /// The Fast table: visibly more aggressive bots and the decisive-hand boost.
    public static let fast = TableRules(
        style: .fast, smallBlind: 20, bigBlind: 40, buyIn: 1000,
        personalities: WorldPersonalities.fast, decisiveHandBoost: true)

    // MARK: - Skypool tables (D-065/D-066)
    //
    // The Skypool hosts the same two generic Texas formats as the Riverwood, but with
    // its own tougher URBAN bots and buy-ins ~5× the corresponding Riverwood tables
    // (Riverwood Texas = 1000 → Skypool ≈ 5000), on an increasing scale: Fast the
    // cheapest, Classic a little more. Same blinds/formats as the Riverwood — only the
    // stakes (buy-in) and the roster (personalities) change (D-065).

    /// The Skypool Classic Texas table: urban bots, higher buy-in (a little above Fast).
    public static let skypoolClassic = TableRules(
        style: .classic, smallBlind: 100, bigBlind: 200, buyIn: 6000,
        personalities: WorldPersonalities.skypool, decisiveHandBoost: false)

    /// The Skypool Fast Texas table: urban bots (fast variants), the decisive-hand
    /// boost, and the cheapest Skypool buy-in.
    public static let skypoolFast = TableRules(
        style: .fast, smallBlind: 100, bigBlind: 200, buyIn: 5000,
        personalities: WorldPersonalities.skypoolFast, decisiveHandBoost: true)
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

    // MARK: - Skypool (urban) personalities (D-066)
    //
    // The three Skypool archetypes are the same three characters — novice / rock /
    // aggressor — TRANSPLANTED TO THE CITY. They are declared as their OWN entities
    // (full literals, not parametric variants of the Riverwood presets) DELIBERATELY:
    // it lets them diverge over time without ever touching the frontier personalities.
    // Continuity of character, change of setting — the player recognises the archetype
    // and feels the place has changed, not the cast. They turn existing levers only
    // (no new dimensions), including the Omaha ones (omahaCoordination/omahaNuttiness,
    // D-063). NOT calibrated against the Riverwood yet — that comparison is a later
    // brick, judged by the user after playing both places. Slots: novice/rock/aggressor.
    public static let skypool: [Personality] = [
        // Urban novice: a city kid, new to the game, a little less naive than the
        // frontier boy (a touch more rational, less tilty) but still not careful —
        // plays too much and gambles with city money.
        Personality(name: "Skypool Rookie",
                    tightness: 0.25, aggression: 0.55, bluffFrequency: 0.40, riskTolerance: 0.45,
                    positionAwareness: 0.25, rationality: 0.45, tiltReactivity: 0.60,
                    pressureResistance: 0.55, trashFoldTendency: 0.20,
                    drawDiscipline: 0.30, drawBluffiness: 0.20, openingDiscipline: 0.55,
                    omahaCoordination: 0.30, omahaNuttiness: 0.35),
        // Urban rock: even colder and more professional than the frontier rock, with a
        // touch more affability — plays a hair wider and mixes it up just slightly.
        Personality(name: "Skypool Professional",
                    tightness: 0.85, aggression: 0.30, bluffFrequency: 0.10, riskTolerance: 0.35,
                    positionAwareness: 0.75, rationality: 0.95, tiltReactivity: 0.05,
                    pressureResistance: 0.60, trashFoldTendency: 0.85,
                    drawDiscipline: 0.92, drawBluffiness: 0.08, openingDiscipline: 0.95,
                    omahaCoordination: 0.90, omahaNuttiness: 0.90),
        // Urban aggressor: even more risk-loving than the frontier one — deep city
        // pockets make the gamble cost less, so he calls big out of pride and plays
        // almost everything, loose with non-nut hands in Omaha.
        Personality(name: "Skypool Shark",
                    tightness: 0.25, aggression: 0.97, bluffFrequency: 0.62, riskTolerance: 0.95,
                    positionAwareness: 0.25, rationality: 0.55, tiltReactivity: 0.45,
                    pressureResistance: 0.92, trashFoldTendency: 0.08,
                    drawDiscipline: 0.50, drawBluffiness: 0.80, openingDiscipline: 0.20,
                    omahaCoordination: 0.30, omahaNuttiness: 0.25),
    ]

    // MARK: - Riverwood "Sala Whiskey" — Five-Card Draw roster (D-082)
    //
    // The Whiskey table used the shared starting roster, which is tuned for TEXAS.
    // A personality is not right or wrong in the abstract — it is right or wrong IN
    // THE ECONOMY OF ITS TABLE (CONVENTIONS §1-bis). At a 10-ante / 20-40 LIMIT draw
    // table the cost of seeing the exchange is trivial, so the two dials that make a
    // bot walk away before the draw were both wrong here:
    //
    //   • trashFoldTendency — now largely REDUNDANT: with real equity (D-082) the
    //     bot already declines hopeless holdings on the maths. Left high it fired a
    //     SECOND, blind fold on top, before the exchange that could rescue the hand.
    //   • tightness — the rock's 0.90 raises its bar by +0.12 on the equity scale,
    //     which at these stakes is the difference between "prudent" and "never puts
    //     a chip in play", i.e. unkillable (a wall, not a hard opponent).
    //
    // What is NOT touched is each character's SIGNATURE: the rock still never bluffs
    // (0.03) and never opens without provable openers (0.95); the aggressor keeps its
    // reckless openingDiscipline of 0.20 — its light opening is now made sane by the
    // structural fold-out gate in the bot (D-082), NOT by dulling its character; the
    // novice keeps its low pressureResistance, i.e. it is still the one you can bully.
    public static let riverwoodWhiskey: [Personality] = [
        Personality(name: "Whiskey Novice",         // novice slot
                    tightness: 0.20, aggression: 0.45, bluffFrequency: 0.30, riskTolerance: 0.30,
                    positionAwareness: 0.15, rationality: 0.30, tiltReactivity: 0.80,
                    pressureResistance: 0.35,   // still scared off by big bets — its signature
                    trashFoldTendency: 0.08,    // equity decides now, not a blind second fold
                    drawDiscipline: 0.25, drawBluffiness: 0.15, openingDiscipline: 0.50),
        Personality(name: "Whiskey Rock",           // rock slot
                    tightness: 0.68,            // prudent, but its chips circulate (was 0.90)
                    aggression: 0.28, bluffFrequency: 0.03, riskTolerance: 0.32,
                    positionAwareness: 0.70, rationality: 0.90, tiltReactivity: 0.10,
                    pressureResistance: 0.50,
                    trashFoldTendency: 0.20,    // was 0.90 — it folded before the draw on a coin flip
                    drawDiscipline: 0.90, drawBluffiness: 0.05, openingDiscipline: 0.95),
        Personality(name: "Whiskey Aggressor",      // aggressor slot
                    tightness: 0.35, aggression: 0.90, bluffFrequency: 0.50, riskTolerance: 0.80,
                    positionAwareness: 0.20, rationality: 0.55, tiltReactivity: 0.55,
                    pressureResistance: 0.75, trashFoldTendency: 0.05,
                    drawDiscipline: 0.50, drawBluffiness: 0.80,
                    openingDiscipline: 0.20),   // UNCHANGED: character kept, absurdity fixed in the bot
    ]

    /// Skypool FAST-table variants of the urban archetypes: pushier and looser still
    /// (higher aggression/risk/pressureResistance, lower tightness/trashFold), to keep
    /// the Fast table's dramatic clash — the same relationship the Riverwood's `fast`
    /// has to its `classic` roster. Own literals; the Omaha levers are inert at Texas.
    public static let skypoolFast: [Personality] = [
        Personality(name: "Skypool Fast Rookie",
                    tightness: 0.18, aggression: 0.72, bluffFrequency: 0.52, riskTolerance: 0.62,
                    positionAwareness: 0.25, rationality: 0.50, tiltReactivity: 0.60,
                    pressureResistance: 0.70, trashFoldTendency: 0.10,
                    omahaCoordination: 0.30, omahaNuttiness: 0.35),
        Personality(name: "Skypool Fast Professional",
                    tightness: 0.60, aggression: 0.55, bluffFrequency: 0.28, riskTolerance: 0.50,
                    positionAwareness: 0.70, rationality: 0.85, tiltReactivity: 0.15,
                    pressureResistance: 0.80, trashFoldTendency: 0.65,
                    omahaCoordination: 0.90, omahaNuttiness: 0.90),
        Personality(name: "Skypool Fast Shark",
                    tightness: 0.18, aggression: 0.99, bluffFrequency: 0.75, riskTolerance: 0.98,
                    positionAwareness: 0.25, rationality: 0.55, tiltReactivity: 0.45,
                    pressureResistance: 0.95, trashFoldTendency: 0.05,
                    omahaCoordination: 0.30, omahaNuttiness: 0.25),
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
