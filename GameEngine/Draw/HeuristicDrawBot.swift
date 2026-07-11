// HeuristicDrawBot.swift
// =====================================================================
// A concrete Five-Card Draw bot: a shared baseline (five-card strength + pot
// odds + textbook discards) MODULATED by a `Personality`, reusing the exact
// three Texas presets plus the draw-specific dials (D-010, extended in D-038).
//
// It is honest (reads only its `DrawBotContext`/`DrawDrawContext`) and
// deterministic (its only randomness is a `SeededGenerator` seeded from the
// bot's own `seed` mixed with the context fingerprint, so the same bot in the
// same spot always decides the same way).
//
// Where the three draw dials bite:
//   • openingDiscipline — whether the bot ever bluff-opens without jacks (low =
//     risks being exposed at showdown, D-039).
//   • drawDiscipline    — how often it follows the textbook discard vs a noisy one.
//   • drawBluffiness    — how often it stands pat / short-draws to fake strength.
//
// Foundation only.

import Foundation

public struct HeuristicDrawBot: DrawBot {
    public let personality: Personality
    /// The bot's "soul seed": its identity for reproducible randomness.
    public let seed: UInt64

    public init(personality: Personality, seed: UInt64) {
        self.personality = personality
        self.seed = seed
    }

    // MARK: - Betting

    public func decideAction(_ context: DrawBotContext) -> DrawAction {
        let legal = context.legal
        let p = personality
        // CONTEXTUAL boost for a decisive hand (D-053): more aggression and less
        // trash-folding, applied to THIS decision only — the permanent Personality is
        // untouched. No boost (bonus 0 / scale 1) reproduces the normal behaviour.
        let aggression = (p.aggression + context.aggressionBonus).clamped01
        let trashFold = (p.trashFoldTendency * context.trashFoldScale).clamped01
        var rng = SeededGenerator(seed: botMix64(seed ^ context.fingerprint))

        // Perceived strength: the made hand, coloured by fallibility and tilt.
        let raw = DrawStrategy.strength(context.cards)
        let noise = (botUnit(&rng) - 0.5) * (1.0 - p.rationality) * 0.30
        let tilt = context.emotionalTemperature * p.tiltReactivity
        let perceived = (raw + noise + tilt * 0.12).clamped01

        let potOdds = context.toCall > 0
            ? Double(context.toCall) / Double(context.potSize + context.toCall)
            : 0
        let continueBar = (potOdds + (p.tightness - 0.5) * 0.30 - p.riskTolerance * 0.20 - tilt * 0.10).clamped01
        let valueBar = clamp(0.72 - 0.32 * aggression - tilt * 0.10, low: 0.30, high: 0.95)

        let roll = botUnit(&rng)
        let raiseWhenStrong = 0.35 + 0.60 * aggression
        let bluffChance = p.bluffFrequency * (0.25 + 0.75 * aggression)

        // Pressure: a big bet (> ~60% of the pot) demands more equity to call,
        // inversely to pressureResistance — mostly bites in the big-bet second
        // round, making a post-draw bluff work against a pressure-shy bot (D-048).
        let potBefore = Double(max(1, context.potSize - context.toCall))
        let betFraction = Double(context.toCall) / potBefore
        let callBar = min(0.98, continueBar *
            Personality.callThresholdMultiplier(betFraction: betFraction, pressureResistance: p.pressureResistance))

        // First-round trash fold: a clearly weak pre-draw hand facing a bet is
        // folded with probability trashFoldTendency (D-048). Drawn AFTER `roll` so
        // non-garbage decisions are unchanged.
        if context.phase == .firstBet, context.currentBet > 0, trashFold > 0,
           DrawStrategy.isPreDrawGarbage(context.cards), botUnit(&rng) < trashFold {
            return .fold
        }

        if context.currentBet == 0 {
            // Nobody has bet: check, or open.
            if legal.canBet {
                if legal.hasOpeners {
                    // A legitimate open: value-bet when strong, occasionally thin.
                    if perceived >= valueBar && roll < raiseWhenStrong { return .bet }
                    if perceived < continueBar && roll < bluffChance * 0.5 { return .bet }
                    return .check
                } else {
                    // No openers: only a discipline-gated bluff-open (D-039). A
                    // strict bot (high openingDiscipline) never does this.
                    let bluffOpen = (1.0 - p.openingDiscipline) * bluffChance
                    if roll < bluffOpen { return .bet }
                    return .check
                }
            }
            return legal.canCheck ? .check : .fold
        } else {
            // Facing a bet: fold / call / raise (opening rules no longer bind).
            if perceived >= valueBar && roll < raiseWhenStrong && legal.canRaise { return .raise }
            if perceived >= callBar { return legal.canCall ? .call : .fold }   // pressure-adjusted (D-048)
            if roll < bluffChance && legal.canRaise { return .raise }
            return .fold
        }
    }

    // MARK: - Drawing

    public func decideDiscards(_ context: DrawDrawContext) -> [Card] {
        let p = personality
        // A distinct mask so the draw RNG stream never coincides with the betting one.
        var rng = SeededGenerator(seed: botMix64(seed ^ context.fingerprint ^ 0x5DEC_A5D5_0F00_D1CE))

        let optimal = DrawStrategy.optimalDiscards(from: context.cards)

        // Disciplined bots follow the textbook; undisciplined ones draw noisily.
        if botUnit(&rng) < p.drawDiscipline {
            // A deceptive bot occasionally keeps an extra card (short-draws) to
            // misrepresent strength — bluffiness in the exchange.
            if !optimal.isEmpty && botUnit(&rng) < p.drawBluffiness * 0.5 {
                return Array(optimal.dropLast())
            }
            return optimal
        } else {
            // Noisy exchange: a random legal number of arbitrary cards.
            let n = Int(rng.next() % 5)                 // 0…4
            return Array(context.cards.shuffled(using: &rng).prefix(n))
        }
    }
}
