// MachiavelliMatchmaker.swift
// =====================================================================
// The progressive encounter system for Machiavelli (D-070). A game seats ONE or TWO
// opponents, so at least one archetype is always absent — and WHICH ones appear shifts
// as the player progresses. The point is not a rising difficulty number: the player
// should meet PEOPLE. Early games almost always bring the student; then the student or
// the adult; then the two together; later the professor is introduced; eventually a
// game against the professor alone.
//
// The progression is keyed on GAMES PLAYED — a counter, never elapsed time (D-064/
// D-070 accessibility rule: a blind player takes more real time for the same amount of
// play; a time threshold would punish listening speed, not choices). Deterministic
// given a seed (tests) / random in production, like every other RNG in the project.
//
// This is world/progression logic (it reads `Personality` presets from GameEngine but
// decides who sits down), so it lives in GameWorld. It returns personalities; the
// caller assigns each a distinct bot seed.

import Foundation
import GameEngine

/// Selects the opponents for a Machiavelli game based on how many games the player has
/// already played.
public enum MachiavelliMatchmaker {

    /// A weighted roster: the archetypes seated together and the weight of this option.
    private struct Option { let roster: [Personality]; let weight: Int }

    private static let student = Personality.machiavelliStudent
    private static let adult = Personality.machiavelliAdult
    private static let professor = Personality.machiavelliProfessor

    /// The weighted opponent options for a given progression stage. The professor is
    /// absent until stage 3 (games 7+), rare when introduced, and eventually appears
    /// alone — so the table grows from a lone student to a lone master over a career.
    private static func options(gamesPlayed: Int) -> [Option] {
        switch gamesPlayed {
        case ..<3:                       // just arrived: almost always the student
            return [Option(roster: [student], weight: 90),
                    Option(roster: [adult], weight: 10)]
        case 3..<7:                      // the adult starts to appear
            return [Option(roster: [student], weight: 55),
                    Option(roster: [adult], weight: 35),
                    Option(roster: [student, adult], weight: 10)]
        case 7..<13:                     // both together; the professor is glimpsed
            return [Option(roster: [student], weight: 30),
                    Option(roster: [adult], weight: 35),
                    Option(roster: [student, adult], weight: 25),
                    Option(roster: [professor], weight: 10)]
        case 13..<21:                    // the professor is a regular now
            return [Option(roster: [student], weight: 15),
                    Option(roster: [adult], weight: 25),
                    Option(roster: [student, adult], weight: 25),
                    Option(roster: [professor], weight: 20),
                    Option(roster: [adult, professor], weight: 15)]
        default:                         // a seasoned career: often the master, alone
            return [Option(roster: [adult], weight: 15),
                    Option(roster: [student, adult], weight: 20),
                    Option(roster: [professor], weight: 30),
                    Option(roster: [adult, professor], weight: 25),
                    Option(roster: [student, professor], weight: 10)]
        }
    }

    /// The opponents for the next game, chosen from the stage's weighted options with
    /// the supplied generator (deterministic given its seed). Returns 1–2 personalities.
    public static func opponents(gamesPlayed: Int, using rng: inout SeededGenerator) -> [Personality] {
        let options = options(gamesPlayed: max(0, gamesPlayed))
        let total = options.reduce(0) { $0 + $1.weight }
        var pick = Int(rng.next() % UInt64(total))
        for option in options {
            pick -= option.weight
            if pick < 0 { return option.roster }
        }
        return options.last!.roster
    }

    /// Convenience: choose opponents deterministically from a seed (production passes a
    /// fresh random seed; tests a fixed one).
    public static func opponents(gamesPlayed: Int, seed: UInt64) -> [Personality] {
        var rng = SeededGenerator(seed: seed)
        return opponents(gamesPlayed: gamesPlayed, using: &rng)
    }
}
