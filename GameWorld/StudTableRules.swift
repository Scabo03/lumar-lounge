// StudTableRules.swift
// =====================================================================
// A Seven-Card Stud Pot Limit table's configuration (D-077): the ante/bring-in/bet
// stakes, the buy-in, the two seated bot personalities, the HOUSE PRIZE (D-078), and an
// optional session-acceleration schedule. Parallel to `TableRules`/`DrawTableRules`/
// `OmahaTableRules`. The bot personalities are defined HERE, in GameWorld — the engine
// only receives personalities as input, it never decides them (CONVENTIONS).
//
// GameWorld only.

import Foundation
import GameEngine

public struct StudTableRules: Equatable, Sendable {
    public let ante: Int
    public let bringIn: Int
    /// The minimum full bet size (the "small bet" analogue; Pot Limit governs the rest).
    public let bet: Int
    public let buyIn: Int
    /// The two bot personalities seated against the player.
    public let personalities: [Personality]
    /// The flat prize the House adds to the player's pot each time they win a hand
    /// (D-078). 0 disables it.
    public let housePrize: Int
    /// Optional session acceleration (D-064), keyed on played hands. `.none` here.
    public let escalation: StakeEscalation

    public init(ante: Int, bringIn: Int, bet: Int, buyIn: Int,
                personalities: [Personality], housePrize: Int, escalation: StakeEscalation = .none) {
        self.ante = ante
        self.bringIn = bringIn
        self.bet = bet
        self.buyIn = buyIn
        self.personalities = personalities
        self.housePrize = housePrize
        self.escalation = escalation
    }

    /// The ClockTower's Seven-Card Stud table (D-077/D-078): the most COMPLEX poker game,
    /// against two of the tower's learned regulars, buy-in 3000 (the highest of the
    /// ClockTower — money, not prestige, is the register of THIS table, D-078). Ante 25 /
    /// bring-in 25 / full bet 50 with a 3000 stack — deep, so the Pot-Limit betting has
    /// room to breathe. The House prize (D-079) is paid at CASH-OUT, only if the player
    /// BEATS THE TABLE (busts both opponents).
    ///
    /// The two seated opponents are the STUDENT and the PROFESSOR — a deliberate MIX
    /// (D-078): the brilliant-but-green student is a soft spot the player can beat first;
    /// the old master is the wall. Beating BOTH is the impresa the House rewards (D-079).
    /// (The adult / il Bibliotecario preset exists for a future third seat.)
    /// PACE (D-084) — the ClockTower is the ONE table whose stakes were deliberately NOT
    /// doubled. Its Pot-Limit ceiling is the size of the pot, so raising the ante/bet
    /// would not merely speed the session up, it would make every hand more VIOLENT
    /// (bigger pots ⇒ bigger maximum bets), and low stakes are part of what this place
    /// IS. Instead the session is accelerated with `StakeEscalation` (D-064): hand one
    /// stays exactly as cheap as it is today — the tower's identity is untouched — and
    /// the stakes only tighten as the session runs on.
    public static let clockTower = StudTableRules(
        ante: 25, bringIn: 25, bet: 50, buyIn: 3000,
        personalities: [WorldPersonalities.clockTowerStudent, WorldPersonalities.clockTowerProfessor],
        housePrize: HousePrize.clockTowerStud,
        escalation: StakeEscalation(interval: 10, factor: 1.5))
}

// MARK: - The House Prize economy (D-078 → moved in D-079)

/// The ClockTower Stud "House Prize" — a one-time reward the House pays the player for
/// BEATING THE TABLE (eliminating both opponents). It is NOT a rake, not a tax, and NOT a
/// per-hand cashback: it is the recognition of an IMPRESA — you beat the Professor, you
/// didn't merely scrape a profit. It rewards winning the hardest game outright.
///
/// **Why it moved (D-079).** It was first paid every hand the player won (D-078), added to
/// their table chips. But injecting chips into a live session is NEVER neutral in poker: the
/// stacks are a strategic lever and the BOTS SEE THEM — in Pot Limit the betting cap depends
/// on stacks and the pot, so a mid-session bonus turns a hand-win into a compounding
/// structural advantage (a snowball), not a reward. So the prize is now paid ONLY at the end,
/// ONLY on a full-table win, and it never touches a table stack — the ONLY chip injection at
/// the table is the buy-in (invariant restored, D-079).
///
/// It is an ECONOMY/SESSION mechanic, so it lives in GameWorld (like buy-in, `PlayerAccount`,
/// `StakeEscalation`, `MachiavelliRefund`), NOT in the engine — the `StudHand` and the
/// `StudSessionDriver` (the table) know NOTHING about it. It is applied purely at CASH-OUT,
/// mirroring the Machiavelli refund: a GameWorld pure function the table's view model calls.
public enum HousePrize {

    /// The one-time prize for beating the ClockTower Stud table (D-079). Calibrated to the
    /// 3000 buy-in and to the RARITY of the feat — busting both regulars, including the
    /// patient, unshakeable Professor, is an impresa: half a buy-in (1500) is a real
    /// recognition, clearly perceptible on top of the ~6000 net the player already won by
    /// taking the whole table, without turning the table into a money machine (it fires at
    /// most once, and only on a full-table win). Verified with `DEBUG_FREE_PLAY` OFF.
    public static let clockTowerStud = 1500

    /// Whether the player BEAT THE TABLE: they survive with chips AND every opponent has been
    /// eliminated (zero chips). Pure, testable — the sole condition for the prize (D-079).
    public static func beatTheTable(heroChips: Int, opponentChips: [Int]) -> Bool {
        heroChips > 0 && !opponentChips.isEmpty && opponentChips.allSatisfy { $0 == 0 }
    }

    /// The chips the player cashes out at session end: their remaining table chips, PLUS the
    /// prize ONLY if they beat the table. The prize is thus never in a table stack — it is
    /// added here, at the persistent-chips boundary (D-079).
    public static func cashOut(heroChips: Int, opponentChips: [Int], prize: Int) -> Int {
        heroChips + (beatTheTable(heroChips: heroChips, opponentChips: opponentChips) ? prize : 0)
    }
}

// MARK: - ClockTower poker personalities (D-078)

public extension WorldPersonalities {

    /// The ClockTower's poker personalities — the same three regulars the Machiavelli
    /// table knows (lo Studente / il Bibliotecario / il Professore), now built as POKER
    /// players with the poker levers (D-078). They are intellectuals who play cards: not
    /// the Riverwood's frontier gamblers nor the Skypool's cold professionals. The new
    /// `studBoardReading` dial (D-076) separates them further — the master reads the
    /// boards, the student barely does. NOT calibrated against the other casinos yet.

    /// The STUDENT — brilliant but inexperienced: plays too many hands, over-aggressive,
    /// bluffs a lot, and reads opponents' boards poorly. A soft spot the player can beat.
    static let clockTowerStudent = Personality(
        name: "ClockTower Student",
        tightness: 0.35, aggression: 0.62, bluffFrequency: 0.42, riskTolerance: 0.58,
        positionAwareness: 0.45, rationality: 0.68, tiltReactivity: 0.50,
        pressureResistance: 0.50, trashFoldTendency: 0.25, studBoardReading: 0.35)

    /// The ADULT — il Bibliotecario: methodical, solid, in the middle on every axis. A
    /// careful, unshowy player. (Defined for a future third seat; not seated by default.)
    static let clockTowerAdult = Personality(
        name: "ClockTower Librarian",
        tightness: 0.58, aggression: 0.48, bluffFrequency: 0.22, riskTolerance: 0.40,
        positionAwareness: 0.65, rationality: 0.85, tiltReactivity: 0.20,
        pressureResistance: 0.60, trashFoldTendency: 0.60, studBoardReading: 0.65)

    /// The PROFESSOR — an old master who has seen everything: patient, selective, sharp,
    /// nearly unshakeable, and the finest board reader at the table. Raises with the goods,
    /// respects real strength (folds to it), rarely bluffs. The wall.
    static let clockTowerProfessor = Personality(
        name: "ClockTower Professor",
        tightness: 0.72, aggression: 0.55, bluffFrequency: 0.18, riskTolerance: 0.42,
        positionAwareness: 0.75, rationality: 0.95, tiltReactivity: 0.08,
        pressureResistance: 0.55, trashFoldTendency: 0.80, studBoardReading: 0.95)

    /// The two Stud opponents seated at the ClockTower, in position order: student then
    /// professor (D-078).
    static let clockTowerStud: [Personality] = [clockTowerStudent, clockTowerProfessor]
}
