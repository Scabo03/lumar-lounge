// OmahaTableRules.swift
// =====================================================================
// The configuration of an Omaha Pot Limit table: blinds, buy-in, the bot roster,
// and the session-acceleration schedule (D-064). Parallel to `TableRules` (Texas)
// and `DrawTableRules` (Draw). No casino identity is expressed here — where an Omaha
// table is hosted is a later, separate brick.
//
// GameWorld only.

import Foundation
import GameEngine

public struct OmahaTableRules: Equatable, Sendable {
    public let smallBlind: Int
    public let bigBlind: Int
    public let buyIn: Int
    /// The three bot personalities seated against the player.
    public let personalities: [Personality]
    /// The session-acceleration schedule: blinds ratchet up every N PLAYED hands so a
    /// long Pot-Limit session ends. Keyed on hands played, never on time (D-064).
    public let escalation: StakeEscalation

    public init(smallBlind: Int, bigBlind: Int, buyIn: Int,
                personalities: [Personality], escalation: StakeEscalation = .none) {
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.buyIn = buyIn
        self.personalities = personalities
        self.escalation = escalation
    }

    /// A standard Pot Limit Omaha table: blinds escalate every 12 played hands by
    /// 1.5× (tournament-style) so the session tightens and ends (D-064). The precise
    /// numbers are a starting point, to be tuned when Omaha becomes playable.
    public static let standard = OmahaTableRules(
        smallBlind: 5, bigBlind: 10, buyIn: 1000,
        personalities: [.eagerNovice, .conservativeRock, .hotAggressor],
        escalation: StakeEscalation(interval: 12, factor: 1.5))
}
