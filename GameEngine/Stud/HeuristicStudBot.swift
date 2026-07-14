// HeuristicStudBot.swift
// =====================================================================
// A concrete Seven-Card Stud Pot Limit bot: the shared mathematical baseline (Stud hand
// strength + pot odds) MODULATED by a `Personality`, including the Stud dial
// `studBoardReading` (D-076). It plays Stud AS Stud — weighing its own cards AND reading
// opponents' up cards (dead outs, threatening boards), the defining skill of the game.
//
// Determinism: the only randomness is a SeededGenerator seeded from the bot's own `seed`
// mixed with the context fingerprint, so the same bot facing the same situation always
// chooses the same action. Reads only public info + its own cards (D-009). Foundation only.

import Foundation

public struct HeuristicStudBot: StudBot {
    /// Default Monte Carlo rollouts. Stud evaluates best-five-of-seven (C(7,5)=21) per
    /// player, like Texas; with the usual 2–3 opponents this stays snappy at ~80 samples.
    public static let defaultEquitySamples = 80

    public let personality: Personality
    /// The bot's "soul seed": its identity for reproducible randomness.
    public let seed: UInt64
    /// Monte Carlo rollouts used for post-third-street equity.
    public let equitySamples: Int

    public init(personality: Personality, seed: UInt64, equitySamples: Int = defaultEquitySamples) {
        self.personality = personality
        self.seed = seed
        self.equitySamples = max(1, equitySamples)
    }

    public func decide(_ context: StudBotContext) -> StudAction {
        let legal = context.legal
        let p = personality
        var rng = SeededGenerator(seed: botMix64(seed ^ context.fingerprint))
        let thirdStreet = context.street == .third

        // 1. Perceived strength — honest info only.
        let opponentUp = context.seats.filter { !$0.isHero && !$0.hasFolded }.map { $0.upCards }
        let rawStrength: Double = thirdStreet
            ? StudStrength.thirdStreet(context.heroCards)
            : StudStrength.equity(heroCards: context.heroCards, opponentUpCards: opponentUp,
                                  samples: equitySamples, using: &rng)

        // Board reading (D-076): the scariest opposing board, weighted by how much this
        // bot reads the table. A sharp reader demands more to continue against a menacing
        // board; a blind one plays its own cards regardless.
        let threat = opponentUp.map(StudStrength.boardThreat).max() ?? 0
        let boardPenalty = threat * p.studBoardReading * 0.22

        let noise = (botUnit(&rng) - 0.5) * (1.0 - p.rationality) * 0.35
        let tilt = context.emotionalTemperature * p.tiltReactivity
        let perceived = (rawStrength + noise + tilt * 0.15 - boardPenalty).clamped01

        // 2. Thresholds shaped by personality.
        let potOdds = context.toCall > 0
            ? Double(context.toCall) / Double(context.potSize + context.toCall)
            : 0
        let discipline = (p.tightness - 0.5) * 0.30
        let riskLoosen = p.riskTolerance * 0.20
        let continueBar = (potOdds + discipline - riskLoosen - tilt * 0.15).clamped01
        let valueBar = clamp(0.80 - 0.35 * p.aggression - tilt * 0.10
                             + (context.aggressionFacedThisStreet ? 0.05 : 0), low: 0.35, high: 0.97)

        let roll = botUnit(&rng)
        let bluffChance = p.bluffFrequency * (0.25 + 0.75 * p.aggression)
        let raiseWhenStrong = 0.35 + 0.60 * p.aggression
        let sizeFraction = 0.50 + 0.45 * p.aggression   // 0.50…0.95 of the pot-limit max

        // Pressure (D-048): a big bet demands more equity to call, inversely to
        // pressureResistance.
        let potBefore = Double(max(1, context.potSize - context.toCall))
        let betFraction = Double(context.toCall) / potBefore
        let callBar = min(0.98, continueBar *
            Personality.callThresholdMultiplier(betFraction: betFraction, pressureResistance: p.pressureResistance))

        // Third-street trash fold: a clearly weak three-card start facing a completed bet
        // is folded. Drawn AFTER `roll` so unrelated decisions stay reproducible (D-048).
        let trashBar = 0.28 + 0.12 * p.studBoardReading
        if thirdStreet, context.toCall > 0, rawStrength < trashBar,
           botUnit(&rng) < max(p.trashFoldTendency, 0.5 * threat * p.studBoardReading) {
            return .fold
        }

        // 3. Decide.
        if context.toCall == 0 {
            if perceived >= valueBar && roll < raiseWhenStrong {
                return aggressiveAction(legal, fraction: sizeFraction)
            }
            if perceived < continueBar && roll < bluffChance {
                return aggressiveAction(legal, fraction: sizeFraction)
            }
            return legal.canCheck ? .check : (legal.canCall ? .call : .fold)
        } else {
            if perceived >= valueBar && roll < raiseWhenStrong && legal.canRaise {
                return aggressiveAction(legal, fraction: sizeFraction)
            }
            if perceived >= callBar {
                return legal.canCall ? .call : (legal.canCheck ? .check : .fold)
            }
            if roll < bluffChance && legal.canRaise {
                return aggressiveAction(legal, fraction: sizeFraction)
            }
            return legal.canCheck ? .check : .fold
        }
    }

    /// Turns an "be aggressive" intent into a concrete, always-legal Pot-Limit bet or
    /// raise sized to `fraction` of the way up to the pot ceiling. When the sizing reaches
    /// the seat's stack it is naturally an all-in (the engine flags it). Falls back to
    /// call/check if aggression isn't available.
    private func aggressiveAction(_ legal: StudLegalActions, fraction: Double) -> StudAction {
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
