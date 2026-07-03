// HeuristicBot.swift
// =====================================================================
// A concrete, extensible bot: a shared mathematical baseline (hand strength +
// pot odds + position) MODULATED by a `Personality`. Two HeuristicBots differ
// only in their personality and their seed, not in the maths they can see
// (D-010). It never barà: it reads only its `BotContext`, i.e. public state plus
// its own two cards (D-009).
//
// Determinism: the only randomness is a SeededGenerator seeded from the bot's
// own `seed` mixed with the context fingerprint, so the same bot facing the same
// situation always chooses the same action.
//
// This is deliberately an "ossatura pulita": each ingredient (equity, position,
// pot odds, sizing) can be refined later without rewriting the rest. Foundation
// only.

import Foundation

public struct HeuristicBot: PokerBot {
    public let personality: Personality
    /// The bot's "soul seed": its identity for reproducible randomness.
    public let seed: UInt64
    /// Monte Carlo rollouts used for postflop equity.
    public let equitySamples: Int

    public init(personality: Personality, seed: UInt64, equitySamples: Int = 200) {
        self.personality = personality
        self.seed = seed
        self.equitySamples = max(1, equitySamples)
    }

    public func decide(_ context: BotContext) -> Action {
        let legal = context.legal
        let p = personality
        var rng = SeededGenerator(seed: botMix64(seed ^ context.fingerprint))

        // 1. Perceived strength — honest info only.
        let rawStrength: Double = context.board.isEmpty
            ? HandStrength.preflop(context.hole)
            : HandStrength.equity(hole: context.hole.cards, board: context.board,
                                  opponents: max(1, context.activeOpponents),
                                  samples: equitySamples, using: &rng)

        // Fallibility (low rationality → noisy reads), tilt and position colour
        // the perception.
        let noise = (botUnit(&rng) - 0.5) * (1.0 - p.rationality) * 0.35
        let tilt = context.emotionalTemperature * p.tiltReactivity
        let positionBoost = context.lateness * p.positionAwareness * 0.12
        let perceived = (rawStrength + noise + positionBoost + tilt * 0.15).clamped01

        // 2. Thresholds shaped by personality.
        let potOdds = context.toCall > 0
            ? Double(context.toCall) / Double(context.potSize + context.toCall)
            : 0
        let discipline = (p.tightness - 0.5) * 0.30   // tight demands a margin
        let riskLoosen = p.riskTolerance * 0.20       // risk-lovers call thinner
        let continueBar = (potOdds + discipline - riskLoosen - tilt * 0.15).clamped01
        let valueBar = clamp(0.82 - 0.35 * p.aggression - tilt * 0.10
                             + (context.aggressionFacedThisStreet ? 0.05 : 0), low: 0.35, high: 0.97)

        let roll = botUnit(&rng)
        let bluffChance = p.bluffFrequency * (0.25 + 0.75 * p.aggression)
        let raiseWhenStrong = 0.35 + 0.60 * p.aggression
        let sizeFraction = 0.5 + 0.8 * p.aggression   // 0.5×…1.3× pot

        // 3. Decide.
        if context.toCall == 0 {
            // Nothing to call: we can check for free.
            if perceived >= valueBar && roll < raiseWhenStrong {
                return aggressiveAction(context, legal, fraction: sizeFraction)
            }
            if perceived < continueBar && roll < bluffChance {
                return aggressiveAction(context, legal, fraction: sizeFraction)
            }
            return legal.canCheck ? .check : (legal.canCall ? .call : .fold)
        } else {
            // Facing a bet: fold / call / raise.
            if perceived >= valueBar && roll < raiseWhenStrong && legal.canRaise {
                return aggressiveAction(context, legal, fraction: sizeFraction)
            }
            if perceived >= continueBar {
                return legal.canCall ? .call : (legal.canCheck ? .check : .fold)
            }
            // Weak: mostly give up, sometimes bluff-raise.
            if roll < bluffChance && legal.canRaise {
                return aggressiveAction(context, legal, fraction: sizeFraction)
            }
            return legal.canCheck ? .check : .fold
        }
    }

    /// Turns an "be aggressive" intent into a concrete, always-legal bet/raise
    /// (or all-in when the sizing reaches the stack). Falls back to call/check if
    /// aggression isn't available (e.g. action not reopened).
    private func aggressiveAction(_ context: BotContext, _ legal: LegalActions, fraction: Double) -> Action {
        if legal.canBet {
            var to = Int((Double(max(context.potSize, context.bigBlind)) * fraction).rounded())
            to = max(to, legal.minBetTo)
            if to >= legal.maxBetTo { return legal.canAllIn ? .allIn : .bet(legal.maxBetTo) }
            return .bet(to)
        }
        if legal.canRaise {
            var to = context.currentBet + Int((Double(context.potSize + context.toCall) * fraction).rounded())
            to = max(to, legal.minRaiseTo)
            if to >= legal.maxRaiseTo { return .allIn }
            return .raise(to)
        }
        if legal.canCall { return .call }
        return legal.canCheck ? .check : .fold
    }
}

// MARK: - Small numeric helper

@inline(__always)
func clamp(_ value: Double, low: Double, high: Double) -> Double {
    Swift.min(high, Swift.max(low, value))
}
