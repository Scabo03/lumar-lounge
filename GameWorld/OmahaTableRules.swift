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

    /// The Skypool's "Marble" table — the casino's SPECIALITY (D-065/D-066). Pot Limit
    /// Omaha with the urban roster and the highest buy-in of the three Skypool tables
    /// (sensibly above both Texas tables). Blinds escalate on a played-hands schedule
    /// so a Pot-Limit session tightens and ends (D-064). 25/50 blinds match the deeper
    /// 10000 buy-in (a 200 big-blind stack, standard for PLO).
    public static let skypoolMarble = OmahaTableRules(
        smallBlind: 25, bigBlind: 50, buyIn: 10000,
        personalities: WorldPersonalities.skypool,
        escalation: StakeEscalation(interval: 12, factor: 1.5))
}
