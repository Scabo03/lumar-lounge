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
    /// Whether the ante grows after each pass-and-out (D-052).
    public let progressiveAnte: Bool
    /// Whether decisive hands are enabled (D-053).
    public let decisiveHands: Bool

    public init(ante: Int, smallBet: Int, bigBet: Int, buyIn: Int, personalities: [Personality],
                progressiveAnte: Bool = false, decisiveHands: Bool = false) {
        self.ante = ante
        self.smallBet = smallBet
        self.bigBet = bigBet
        self.buyIn = buyIn
        self.personalities = personalities
        self.progressiveAnte = progressiveAnte
        self.decisiveHands = decisiveHands
    }

    /// The Riverwood's "Sala Whiskey": ante 10, 20/40 limit, 2000 buy-in, the three
    /// starting personalities (D-038), plus the pace mechanics — a progressive ante
    /// (D-052) and decisive hands (D-053) — to keep the traditional draw from dragging.
    public static let riverwoodWhiskey = DrawTableRules(
        ante: 25, smallBet: 50, bigBet: 100, buyIn: 2000,
        personalities: WorldPersonalities.riverwoodWhiskey,
        progressiveAnte: true, decisiveHands: true)
}
