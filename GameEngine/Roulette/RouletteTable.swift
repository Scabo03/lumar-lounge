// RouletteTable.swift
// =====================================================================
// The geometry and colours of a European single-zero roulette wheel and its
// betting layout (D-101).
//
// Roulette is unlike every other game in the project: there are no cards, no
// hand to evaluate, no opponent or house playing a hand of its own — only a
// wager on a random outcome. So this engine shares NOTHING with the others,
// not even the foundational card types (there are no cards); it stands entirely
// on its own in its own subfolder, importing only Foundation.
//
// The layout knowledge lives HERE, pure and tested, because both the future
// betting table and the resolution depend on exactly which numbers a column, a
// dozen, a street, a corner or a six-line covers, and on which numbers are red.
// Getting that wrong is the single largest source of roulette bugs, so it is
// stated once, in one place, and pinned by tests.

import Foundation

/// The colour of a pocket. Zero is green; the other 36 split red/black by the
/// standard European pattern.
public enum RouletteColor: String, Equatable, Sendable {
    case red, black, green
}

public enum RouletteLayout {

    /// The single zero plus 1…36.
    public static let pocketCount = 37
    public static let numbers = Array(1...36)

    /// The red numbers of the European wheel. The rest of 1…36 are black; 0 is green.
    public static let redNumbers: Set<Int> = [1, 3, 5, 7, 9, 12, 14, 16, 18,
                                              19, 21, 23, 25, 27, 30, 32, 34, 36]

    public static func color(of pocket: Int) -> RouletteColor {
        if pocket == 0 { return .green }
        return redNumbers.contains(pocket) ? .red : .black
    }

    // MARK: - The 12×3 grid (1…36)

    /// Row of a number, 1…12 (three numbers per row).
    public static func row(of n: Int) -> Int { (n - 1) / 3 + 1 }
    /// Column of a number, 1…3.
    public static func column(of n: Int) -> Int { (n - 1) % 3 + 1 }

    /// The twelve numbers of a column (1…3): 1 = {1,4,…,34}, 2 = {2,5,…,35}, 3 = {3,6,…,36}.
    public static func columnNumbers(_ c: Int) -> [Int] {
        numbers.filter { column(of: $0) == c }
    }

    /// The twelve numbers of a dozen (1…3): 1–12, 13–24, 25–36.
    public static func dozenNumbers(_ d: Int) -> [Int] {
        Array(((d - 1) * 12 + 1)...(d * 12))
    }

    /// A street (terzina): the three numbers of row `r` (1…12).
    public static func streetNumbers(row r: Int) -> [Int] {
        [3 * r - 2, 3 * r - 1, 3 * r]
    }

    /// A six-line (sestina): two adjacent rows starting at `topRow` (1…11) = six numbers.
    public static func sixLineNumbers(topRow r: Int) -> [Int] {
        streetNumbers(row: r) + streetNumbers(row: r + 1)
    }

    /// A corner (quartina): the four numbers of the square whose top-left is `n`.
    /// Valid only when `n` is in column 1 or 2 (so `n+1` shares its row) and in rows
    /// 1…11 (so `n+3` exists) — otherwise `nil`.
    public static func cornerNumbers(topLeft n: Int) -> [Int]? {
        guard numbers.contains(n), column(of: n) <= 2, row(of: n) <= 11 else { return nil }
        return [n, n + 1, n + 3, n + 4].sorted()
    }
}
