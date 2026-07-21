// RouletteBet.swift
// =====================================================================
// A single roulette wager (D-101): what it covers, what it pays, and how often
// a player reaches for it.
//
// A bet is identified by its KIND and the exact NUMBERS it covers, both derived
// from the standard layout. That identity is what lets the future betting table
// and the register band act on the SAME bet — placing "red" from either one is
// the same key in the same slip, never two implementations of red (D-101, the
// same single-predicate discipline the Machiavelli box and drag share).

import Foundation

public struct RouletteBet: Hashable, Sendable {

    /// The family of a bet, which fixes its odds and whether the zero rule refunds it.
    public enum Kind: String, Hashable, Sendable {
        case straight   // numero pieno — 1 number
        case split      // cavallo — 2 numbers
        case street     // terzina — 3 numbers
        case corner     // quartina — 4 numbers
        case sixLine    // sestina — 6 numbers
        case column     // colonna — 12 numbers
        case dozen      // dozzina — 12 numbers
        case red, black // rosso / nero — 18 numbers
        case even, odd  // pari / dispari — 18 numbers
        case low, high  // manque (1–18) / passe (19–36) — 18 numbers
    }

    public let kind: Kind
    /// The numbers this bet wins on, canonical (sorted, unique).
    public let covered: [Int]

    public init(kind: Kind, covered: [Int]) {
        self.kind = kind
        self.covered = covered.sorted()
    }

    // MARK: - Odds

    /// What the bet pays "to one": a win returns the stake plus this many times it.
    public var oddsToOne: Int {
        switch kind {
        case .straight: return 35
        case .split:    return 17
        case .street:   return 11
        case .corner:   return 8
        case .sixLine:  return 5
        case .column, .dozen: return 2
        case .red, .black, .even, .odd, .low, .high: return 1
        }
    }

    /// The SIMPLE even-money OUTSIDE bets — red/black, even/odd, the two halves.
    /// These are the ones the zero rule refunds in full (D-101). A column or a
    /// dozen also pays "even-ish" but at 2:1 and is NOT a simple even-money bet, so
    /// it loses to zero like any other bet that does not cover it.
    public var isEvenMoneyOutside: Bool {
        switch kind {
        case .red, .black, .even, .odd, .low, .high: return true
        default: return false
        }
    }

    /// The navigation-frequency class (D-101): the accessible table is ordered so the
    /// blind player meets the bets they make MOST OFTEN first — the CONVENTIONS §4
    /// "most-used first" principle applied to a whole table. Lower rank = read sooner.
    ///   0 red/black/even/odd · 1 the halves · 2 dozens & columns ·
    ///   3 the multi-number inside bets · 4 the single numbers (rarest).
    public var frequencyRank: Int {
        switch kind {
        case .red, .black, .even, .odd: return 0
        case .low, .high:               return 1
        case .dozen, .column:           return 2
        case .split, .street, .corner, .sixLine: return 3
        case .straight:                 return 4
        }
    }

    // MARK: - The catalogue of valid bets (the tappeto)

    public static func straight(_ n: Int) -> RouletteBet { RouletteBet(kind: .straight, covered: [n]) }

    /// A split of two numbers. Adjacency is the betting table's business (it only
    /// offers legal splits); the engine just needs the pair.
    public static func split(_ a: Int, _ b: Int) -> RouletteBet {
        RouletteBet(kind: .split, covered: [a, b])
    }

    public static func street(row r: Int) -> RouletteBet {
        RouletteBet(kind: .street, covered: RouletteLayout.streetNumbers(row: r))
    }

    public static func corner(topLeft n: Int) -> RouletteBet? {
        RouletteLayout.cornerNumbers(topLeft: n).map { RouletteBet(kind: .corner, covered: $0) }
    }

    public static func sixLine(topRow r: Int) -> RouletteBet {
        RouletteBet(kind: .sixLine, covered: RouletteLayout.sixLineNumbers(topRow: r))
    }

    public static func column(_ c: Int) -> RouletteBet {
        RouletteBet(kind: .column, covered: RouletteLayout.columnNumbers(c))
    }

    public static func dozen(_ d: Int) -> RouletteBet {
        RouletteBet(kind: .dozen, covered: RouletteLayout.dozenNumbers(d))
    }

    public static let red  = RouletteBet(kind: .red,  covered: Array(RouletteLayout.redNumbers))
    public static let black = RouletteBet(kind: .black,
                                          covered: RouletteLayout.numbers.filter { !RouletteLayout.redNumbers.contains($0) })
    public static let even = RouletteBet(kind: .even, covered: RouletteLayout.numbers.filter { $0 % 2 == 0 })
    public static let odd  = RouletteBet(kind: .odd,  covered: RouletteLayout.numbers.filter { $0 % 2 == 1 })
    public static let low  = RouletteBet(kind: .low,  covered: Array(1...18))   // manque
    public static let high = RouletteBet(kind: .high, covered: Array(19...36))  // passe
}
