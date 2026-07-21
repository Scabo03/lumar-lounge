// RouletteSessionEvent.swift
// =====================================================================
// What the roulette driver NARRATES (D-102): a descriptive, non-prescriptive
// flow of value events, sister of the other games' events (D-015/D-090). The
// events say what HAPPENED — bets placed, wheel spun, spin settled — never what
// the player should do. There are no private cards, so every event is public.

import Foundation
import GameEngine

public struct RouletteSessionEvent: Sendable {
    public let sequence: Int
    public let audience: EventAudience
    public let payload: RouletteEventPayload

    public init(sequence: Int, audience: EventAudience, payload: RouletteEventPayload) {
        self.sequence = sequence
        self.audience = audience
        self.payload = payload
    }
}

public enum RouletteSessionEndReason: Equatable, Sendable {
    case stopped        // the player left
    case brokeTheBank   // no longer able to cover the minimum
}

public enum RouletteEventPayload: Sendable {
    case sessionBegan(chips: Int, minimumBet: Int, maximumBet: Int)
    /// The bets the player confirmed, and the chips left after they were deducted.
    case roundBegan(roundNumber: Int, totalStaked: Int, chips: Int)
    /// The wheel result — the number and its colour. Emitted BEFORE the settlement
    /// so the wheel/ball sound can land on it, and the settlement's outcome sting is
    /// ordered AFTER the line that explains it (D-085), never anticipating the result.
    case wheelSpun(pocket: Int, color: RouletteColor)
    /// The full settlement of the spin — who paid, who lost, the zero refund.
    case roundResolved(resolution: RouletteRoundResolution, chips: Int)
    case roundEnded(roundNumber: Int, net: Int, chips: Int)
    case sessionEnded(reason: RouletteSessionEndReason)
}
