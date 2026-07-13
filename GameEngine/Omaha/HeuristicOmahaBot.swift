// HeuristicOmahaBot.swift
// =====================================================================
// A concrete Omaha Pot Limit bot: the shared mathematical baseline (Omaha hand
// strength + pot odds + position) MODULATED by a `Personality`, including the two
// Omaha dials (`omahaCoordination`, `omahaNuttiness`, D-063). It plays Omaha as
// Omaha — coordination-first pre-flop, nut-disciplined and Pot-Limit-aware post-flop
// — not Texas with four cards.
//
// Determinism: the only randomness is a SeededGenerator seeded from the bot's own
// `seed` mixed with the context fingerprint, so the same bot facing the same
// situation always chooses the same action. Reads only public info + its own four
// cards (D-009). Foundation only.

import Foundation

public struct HeuristicOmahaBot: OmahaBot {
    /// Default Monte Carlo rollouts: ~⅓ of the Texas default, because each Omaha
    /// sample costs ~3× a Texas sample (60 constrained evaluations vs 21), so this
    /// keeps per-decision work — and thus response time — on par with Texas (D-063).
    public static let defaultEquitySamples = 60

    public let personality: Personality
    /// The bot's "soul seed": its identity for reproducible randomness.
    public let seed: UInt64
    /// Monte Carlo rollouts used for postflop equity.
    public let equitySamples: Int

    public init(personality: Personality, seed: UInt64, equitySamples: Int = defaultEquitySamples) {
        self.personality = personality
        self.seed = seed
        self.equitySamples = max(1, equitySamples)
    }

    public func decide(_ context: OmahaBotContext) -> OmahaAction {
        let legal = context.legal
        let p = personality
        var rng = SeededGenerator(seed: botMix64(seed ^ context.fingerprint))
        let preflop = context.board.isEmpty

        // 1. Perceived strength — honest info only.
        let rawStrength: Double = preflop
            ? OmahaStrength.preflop(context.hole)
            : OmahaStrength.equity(hole: context.hole, board: context.board,
                                   opponents: max(1, context.activeOpponents),
                                   samples: equitySamples, using: &rng)

        let noise = (botUnit(&rng) - 0.5) * (1.0 - p.rationality) * 0.35
        let tilt = context.emotionalTemperature * p.tiltReactivity
        let positionBoost = context.lateness * p.positionAwareness * 0.12
        let perceived = (rawStrength + noise + positionBoost + tilt * 0.15).clamped01

        // 2. Thresholds shaped by personality.
        let potOdds = context.toCall > 0
            ? Double(context.toCall) / Double(context.potSize + context.toCall)
            : 0
        let discipline = (p.tightness - 0.5) * 0.30
        let riskLoosen = p.riskTolerance * 0.20
        // Omaha coordination raises the pre-flop entry bar: coordinated bots are
        // tighter, requiring their four cards to be worth playing (D-063).
        let coordinationBar = preflop ? p.omahaCoordination * 0.12 : 0
        let continueBar = (potOdds + discipline - riskLoosen + coordinationBar - tilt * 0.15).clamped01
        let valueBar = clamp(0.82 - 0.35 * p.aggression - tilt * 0.10
                             + (context.aggressionFacedThisStreet ? 0.05 : 0), low: 0.35, high: 0.97)

        let roll = botUnit(&rng)
        let bluffChance = p.bluffFrequency * (0.25 + 0.75 * p.aggression)
        let raiseWhenStrong = 0.35 + 0.60 * p.aggression
        let sizeFraction = 0.55 + 0.45 * p.aggression   // 0.55…1.0 of the pot-limit max

        // Pressure (D-048) + nut discipline (D-063): a big bet demands more equity to
        // call, inversely to pressureResistance; a nut-disciplined bot demands even
        // more, because a merely-made non-nut hand is a Pot-Limit trap.
        let potBefore = Double(max(1, context.potSize - context.toCall))
        let betFraction = Double(context.toCall) / potBefore
        let nutPenalty = p.omahaNuttiness * min(1.0, betFraction) * 0.20
        let callBar = min(0.98, continueBar *
            Personality.callThresholdMultiplier(betFraction: betFraction, pressureResistance: p.pressureResistance)
            + nutPenalty)

        // Pre-flop trash fold: an uncoordinated / weak four-card hand facing a bet is
        // folded — driven by BOTH trashFoldTendency and omahaCoordination (a
        // coordination-demanding bot treats more hands as unplayable, D-063). Drawn
        // after `roll` so unrelated decisions stay reproducible.
        let omahaGarbage = 0.30 + 0.15 * p.omahaCoordination
        if preflop, context.toCall > 0, rawStrength < omahaGarbage,
           botUnit(&rng) < max(p.trashFoldTendency, p.omahaCoordination) {
            return .fold
        }

        // 3. Decide.
        if context.toCall == 0 {
            if perceived >= valueBar && roll < raiseWhenStrong {
                return aggressiveAction(context, legal, fraction: sizeFraction)
            }
            if perceived < continueBar && roll < bluffChance {
                return aggressiveAction(context, legal, fraction: sizeFraction)
            }
            return legal.canCheck ? .check : (legal.canCall ? .call : .fold)
        } else {
            if perceived >= valueBar && roll < raiseWhenStrong && legal.canRaise {
                return aggressiveAction(context, legal, fraction: sizeFraction)
            }
            if perceived >= callBar {
                return legal.canCall ? .call : (legal.canCheck ? .check : .fold)
            }
            if roll < bluffChance && legal.canRaise {
                return aggressiveAction(context, legal, fraction: sizeFraction)
            }
            return legal.canCheck ? .check : .fold
        }
    }

    /// Turns an "be aggressive" intent into a concrete, always-legal Pot-Limit bet or
    /// raise sized to `fraction` of the way up to the pot ceiling (the legal max is
    /// already the pot). When the sizing reaches the seat's stack it is naturally an
    /// all-in bet/raise (the engine flags it). Falls back to call/check if aggression
    /// isn't available.
    private func aggressiveAction(_ context: OmahaBotContext, _ legal: OmahaLegalActions, fraction: Double) -> OmahaAction {
        let f = clamp(fraction, low: 0, high: 1)
        if legal.canBet {
            var to = legal.minBetTo + Int((Double(legal.maxBetTo - legal.minBetTo) * f).rounded())
            to = min(max(to, legal.minBetTo), legal.maxBetTo)
            return .bet(to)
        }
        if legal.canRaise {
            var to = legal.minRaiseTo + Int((Double(legal.maxRaiseTo - legal.minRaiseTo) * f).rounded())
            to = min(max(to, legal.minRaiseTo), legal.maxRaiseTo)
            return .raise(to)
        }
        if legal.canCall { return .call }
        return legal.canCheck ? .check : .fold
    }
}
