// Personality.swift
// =====================================================================
// A bot's personality: a set of tuning knobs that MODULATE how the shared
// mathematical baseline is expressed, rather than replacing it. Two bots with
// the same cards and the same maths can act very differently depending on their
// personality (see D-010).
//
// The dimensions here are a sensible starting subset; adding more later is
// purely additive (a new stored property with a neutral default plus its use in
// the decision logic). Foundation only.
//
// NOTE: `name` is an English debug identifier, never shown to the player. Any
// user-facing personality label will come from localized strings in UI.

import Foundation

/// How a bot colours its decisions. Every value is a 0…1 dial.
public struct Personality: Equatable, Sendable {
    /// Debug identifier (English, non-user-facing).
    public let name: String
    /// How strong a hand the bot needs to enter/continue. High = folds a lot.
    public let tightness: Double
    /// Tendency to bet/raise rather than call/check when it does play.
    public let aggression: Double
    /// How often it fires a bet/raise with a weak hand (a bluff).
    public let bluffFrequency: Double
    /// Willingness to commit chips on uncertain equity (loosens pot-odds).
    public let riskTolerance: Double
    /// How much position shifts its thresholds. Low = ignores position.
    public let positionAwareness: Double
    /// How closely it follows the maths. Low = noisy, fallible perception.
    public let rationality: Double
    /// How much a recent swing (tilt) pushes it off its baseline.
    public let tiltReactivity: Double

    public init(name: String,
                tightness: Double,
                aggression: Double,
                bluffFrequency: Double,
                riskTolerance: Double,
                positionAwareness: Double,
                rationality: Double,
                tiltReactivity: Double) {
        self.name = name
        self.tightness = tightness.clamped01
        self.aggression = aggression.clamped01
        self.bluffFrequency = bluffFrequency.clamped01
        self.riskTolerance = riskTolerance.clamped01
        self.positionAwareness = positionAwareness.clamped01
        self.rationality = rationality.clamped01
        self.tiltReactivity = tiltReactivity.clamped01
    }
}

public extension Personality {

    /// "Principiante emotivo": plays far too many hands, easily scared off big
    /// bets, improvised bluffs, very emotional. Mathematically simple.
    static let eagerNovice = Personality(
        name: "Eager Novice",
        tightness: 0.20,        // enters almost anything
        aggression: 0.45,
        bluffFrequency: 0.30,   // spur-of-the-moment bluffs
        riskTolerance: 0.25,    // folds when the pressure is real
        positionAwareness: 0.15,
        rationality: 0.30,      // fallible reads
        tiltReactivity: 0.80    // rides its emotions
    )

    /// "Sasso conservativo": only strong hands, little aggression, predictable,
    /// disciplined, unshakeable. Mathematically solid but transparent.
    static let conservativeRock = Personality(
        name: "Conservative Rock",
        tightness: 0.90,        // waits for premium holdings
        aggression: 0.20,
        bluffFrequency: 0.03,   // essentially never bluffs
        riskTolerance: 0.30,
        positionAwareness: 0.70,
        rationality: 0.90,      // sticks to the maths
        tiltReactivity: 0.10    // hard to rattle
    )

    /// "Aggressivo caldo": raises constantly, bluffs a lot, barely reads
    /// position, happy to gamble. Loud and dangerous, but exploitable.
    static let hotAggressor = Personality(
        name: "Hot Aggressor",
        tightness: 0.35,        // plays a wide range
        aggression: 0.90,       // raise-first instinct
        bluffFrequency: 0.50,
        riskTolerance: 0.80,    // loves the gamble
        positionAwareness: 0.20, // ignores position
        rationality: 0.55,
        tiltReactivity: 0.55
    )

    /// The starting roster. More personalities arrive with game progression.
    static let starting: [Personality] = [.eagerNovice, .conservativeRock, .hotAggressor]
}

// MARK: - Small numeric helper

extension Double {
    /// Clamped into the closed unit interval.
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
