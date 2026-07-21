// RouletteBoard.swift
// =====================================================================
// The full set of bets a roulette table OFFERS (D-103), generated once from the
// engine's geometry and grouped for presentation.
//
// The betting table (the tappeto) offers every standard European bet: the
// simple outside bets, the halves, the dozens and columns, every inside
// multi-number bet (splits, streets, corners, six-lines), and every straight-up.
// Enumerating them from the layout keeps the offered bets and the engine in
// lock-step — the same geometry that resolves a spin is the geometry that
// produces the cells, so a cell can never be a bet the resolver would misread.
//
// The bets are grouped so the UI can lay them out visually AND read them by
// FREQUENCY (each group carries its frequency rank, and within a group the
// bets keep a stable order). This is pure and testable — no SwiftUI here.

import Foundation
import GameEngine

public enum RouletteBoard {

    /// A named group of offered bets, with the frequency rank that orders VoiceOver
    /// navigation (lower = read sooner, D-101).
    public struct Group: Equatable, Sendable {
        public let id: String
        public let frequencyRank: Int
        public let bets: [RouletteBet]
    }

    // MARK: - The groups, most-frequent first

    /// Red / black / even / odd — the simplest, most-placed bets.
    public static let simpleEvens: [RouletteBet] = [.red, .black, .even, .odd]

    /// The halves: manque (1–18) and passe (19–36).
    public static let halves: [RouletteBet] = [.low, .high]

    /// The three dozens then the three columns.
    public static let dozensAndColumns: [RouletteBet] =
        [.dozen(1), .dozen(2), .dozen(3), .column(1), .column(2), .column(3)]

    /// Every inside multi-number bet, generated from the layout: splits (cavalli),
    /// streets (terzine), corners (quartine), six-lines (sestine).
    public static let insideMulti: [RouletteBet] = {
        var bets: [RouletteBet] = []
        // Splits with zero (0-1, 0-2, 0-3), then horizontal and vertical splits.
        bets += [.split(0, 1), .split(0, 2), .split(0, 3)]
        for n in RouletteLayout.numbers {
            if RouletteLayout.column(of: n) < 3 { bets.append(.split(n, n + 1)) }   // horizontal
            if RouletteLayout.row(of: n) < 12 { bets.append(.split(n, n + 3)) }     // vertical
        }
        // Streets (12), then corners (all valid), then six-lines (11).
        bets += (1...12).map { RouletteBet.street(row: $0) }
        bets += RouletteLayout.numbers.compactMap { RouletteBet.corner(topLeft: $0) }
        bets += (1...11).map { RouletteBet.sixLine(topRow: $0) }
        return bets
    }()

    /// Every straight-up, zero first then 1…36 — the rarest, read last.
    public static let straights: [RouletteBet] = ([0] + RouletteLayout.numbers).map { RouletteBet.straight($0) }

    /// The groups in presentation/navigation order.
    public static let groups: [Group] = [
        Group(id: "simple",  frequencyRank: 0, bets: simpleEvens),
        Group(id: "halves",  frequencyRank: 1, bets: halves),
        Group(id: "dozcol",  frequencyRank: 2, bets: dozensAndColumns),
        Group(id: "inside",  frequencyRank: 3, bets: insideMulti),
        Group(id: "numbers", frequencyRank: 4, bets: straights),
    ]

    /// Every offered bet, flattened in navigation-frequency order.
    public static let allBets: [RouletteBet] = groups.flatMap { $0.bets }
}
