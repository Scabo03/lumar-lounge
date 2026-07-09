// DrawTableRules.swift
// =====================================================================
// A Five-Card Draw table's configuration (D-042): ante, the two limit bet sizes,
// the buy-in, and the bots' personalities. The draw analogue of the Texas
// `TableRules`. The bots' personalities live HERE in GameWorld — the engine only
// receives them (CONVENTIONS). One table so far: the Riverwood's "Sala Whiskey".

import Foundation
import GameEngine

public struct DrawTableRules: Equatable, Sendable {
    public let ante: Int
    public let smallBet: Int
    public let bigBet: Int
    public let buyIn: Int
    public let personalities: [Personality]   // the three bots

    public init(ante: Int, smallBet: Int, bigBet: Int, buyIn: Int, personalities: [Personality]) {
        self.ante = ante
        self.smallBet = smallBet
        self.bigBet = bigBet
        self.buyIn = buyIn
        self.personalities = personalities
    }

    /// The Riverwood's "Sala Whiskey": ante 10, 20/40 limit, 2000 buy-in, the
    /// three starting personalities (which carry sensible draw dials, D-038).
    public static let riverwoodWhiskey = DrawTableRules(
        ante: 10, smallBet: 20, bigBet: 40, buyIn: 2000,
        personalities: [.eagerNovice, .conservativeRock, .hotAggressor])
}
