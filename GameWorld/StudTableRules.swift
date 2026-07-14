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
    /// room to breathe. The House adds a 200 prize to every hand the player wins.
    ///
    /// The two seated opponents are the STUDENT and the PROFESSOR — a deliberate MIX
    /// (D-078): the brilliant-but-green student is a soft spot the player can beat, so
    /// the house prize is genuinely earnable; the old master is the wall. (The adult /
    /// il Bibliotecario preset exists for a future third seat.)
    public static let clockTower = StudTableRules(
        ante: 25, bringIn: 25, bet: 50, buyIn: 3000,
        personalities: [WorldPersonalities.clockTowerStudent, WorldPersonalities.clockTowerProfessor],
        housePrize: HousePrize.clockTowerStud)
}

// MARK: - The House Prize economy (D-078)

/// The ClockTower Stud "House Prize" — a bonus the House adds to the pot every time the
/// PLAYER wins a hand. It is NOT a rake or a tax: it is an INCENTIVE that rewards winning
/// the hardest game, giving this table a more competitive, money-tied character than the
/// Machiavelli (cerebral, where the winner earns nothing). The ClockTower is still a
/// casino, not just an academic circle: here you CAN earn by your intellect.
///
/// It is an ECONOMY/SESSION mechanic, so it lives in GameWorld (like buy-in, `PlayerAccount`,
/// `StakeEscalation`, `MachiavelliRefund`), NOT in the engine — the `StudHand` never knows
/// about it. The driver adds it to the winner's chips at hand end and narrates it.
public enum HousePrize {

    /// The flat prize added to the player's pot each hand they win at the ClockTower Stud
    /// table (D-078). Calibrated to the 3000 buy-in and the pots this Pot-Limit table
    /// produces: roughly several third-street ante rounds, a small fraction of a contested
    /// pot — PERCEPTIBLE as a reward for winning, but far from a money machine that would
    /// wreck the economy (verified with `DEBUG_FREE_PLAY` OFF on real chip movement).
    public static let clockTowerStud = 200

    /// The prize a player is awarded for a hand: the flat amount when they won, else 0.
    public static func award(won: Bool, prize: Int) -> Int { won ? prize : 0 }
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
