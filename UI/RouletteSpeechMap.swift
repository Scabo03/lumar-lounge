// RouletteSpeechMap.swift
// =====================================================================
// THE outcome narration for roulette (D-102), pure and testable.
//
// Roulette is a fast game — bet, spin, collect, again — so the essential
// announcement is ONE compact line, the same discipline blackjack follows
// (D-091): the number that came up, its colour, which of the player's bets
// paid, and the total won. The detail (each bet and its fiches) lives on the
// interrogable register band, not pushed every spin.
//
// Two rules hold without exception. It DESCRIBES the state and never advises a
// bet (D-091): "17, black, your dozen pays" is description; "you should bet the
// dozen" is advice, and none is given. And the ZERO REFUND is stated plainly, so
// the player understands why they did not lose what they expected (D-101).
//
// The bet names carry French terms (manque / passe) whose pronunciation is not
// yet ear-verified (D-060): they are provisional here and pinned as UNVERIFIED
// until the samples are approved.

import Foundation
import GameEngine
import GameWorld

public enum RouletteSpeechMap {

    public typealias Localizer = (String, [CVarArg]) -> String
    public static let standard: Localizer = { uiLocalizedList($0, $1) }

    /// The single compact outcome line for one settled spin.
    public static func outcomeLine(for r: RouletteRoundResolution,
                                   localized: Localizer = standard) -> String {
        var parts: [String] = []

        // 1. The number and its colour.
        if r.winningPocket == 0 {
            parts.append(localized("roulette.outcome.zero", []))
        } else {
            parts.append(localized("roulette.outcome.number",
                                   [r.winningPocket, color(r.color, localized)]))
        }

        // 2. The zero refund, stated so the player knows why they kept their money.
        if r.zeroRefunded {
            parts.append(localized("roulette.zero.refund", []))
        }

        // 3. Which of the player's bets paid — named when few, counted when many, so
        //    the line stays rapid even with a crowded slip.
        let winners = r.winningResults
        if winners.count == 1 {
            parts.append(localized("roulette.outcome.paid.one", [betName(winners[0].bet, localized: localized)]))
        } else if winners.count > 1 && winners.count <= 3 {
            let names = winners.map { betName($0.bet, localized: localized) }.joined(separator: ", ")
            parts.append(localized("roulette.outcome.paid.some", [names]))
        } else if winners.count > 3 {
            parts.append(localized("roulette.outcome.paid.many", [winners.count]))
        }

        // 4. The bottom line: won, lost, or even.
        if r.net > 0 {
            parts.append(localized("roulette.outcome.won", [r.net]))
        } else if r.net < 0 {
            parts.append(localized("roulette.outcome.lost", [-r.net]))
        } else {
            parts.append(localized("roulette.outcome.even", []))
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Naming

    public static func color(_ c: RouletteColor, _ localized: Localizer) -> String {
        localized("roulette.color.\(c.rawValue)", [])
    }

    /// A bet as the announcement and the register band name it — concise, never advisory.
    public static func betName(_ bet: RouletteBet, localized: Localizer = standard) -> String {
        switch bet.kind {
        case .red:   return localized("roulette.bet.red", [])
        case .black: return localized("roulette.bet.black", [])
        case .even:  return localized("roulette.bet.even", [])
        case .odd:   return localized("roulette.bet.odd", [])
        case .low:   return localized("roulette.bet.low", [])
        case .high:  return localized("roulette.bet.high", [])
        case .dozen:
            return localized("roulette.bet.dozen", [ordinal(dozenIndex(bet), localized)])
        case .column:
            return localized("roulette.bet.column", [ordinal(columnIndex(bet), localized)])
        case .straight:
            return localized("roulette.bet.straight", [bet.covered.first ?? 0])
        case .split:
            let n = bet.covered
            return localized("roulette.bet.split", [n.first ?? 0, n.count > 1 ? n[1] : 0])
        case .street:  return localized("roulette.bet.street", [])
        case .corner:  return localized("roulette.bet.corner", [])
        case .sixLine: return localized("roulette.bet.sixline", [])
        }
    }

    /// The announcement carries money, so it is HIGH — never dropped by the channel
    /// budget (D-085). Roulette has no chatter: nothing here is droppable.
    public static let outcomePriority: AnnouncementPriority = .high

    // MARK: - Helpers

    private static func ordinal(_ n: Int, _ localized: Localizer) -> String {
        localized("roulette.ordinal.\(min(max(n, 1), 3))", [])
    }
    private static func dozenIndex(_ bet: RouletteBet) -> Int {
        ((bet.covered.first ?? 1) - 1) / 12 + 1
    }
    private static func columnIndex(_ bet: RouletteBet) -> Int {
        RouletteLayout.column(of: bet.covered.first ?? 1)
    }
}
