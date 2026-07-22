// RouletteAudioScore.swift
// =====================================================================
// The pacing of a roulette table (D-103), and the physical sounds it plays.
//
// Roulette is a FAST game — bet, spin, collect, again — so the beats are short,
// the same brisk rhythm blackjack keeps (D-091). The one beat that matters is the
// SPIN WAIT: the real wheel mp3 governs it (D-104 — its duration IS the wait, with
// the ball settling over its tail); the short floor below only stands in if the
// file is somehow absent from the bundle.

import Foundation
import Audio
import GameWorld

public enum RoulettePacing {

    /// The felt interval the wheel "turns" for if the wheel mp3 were missing from the
    /// bundle — short, so the wait is a beat, never a disorienting silent freeze
    /// (D-103). With the file delivered (D-104) the view model uses
    /// `audio.duration(of:) ?? spinFloor`, so the real spin governs the wait.
    public static let spinFloor: Double = 1.6

    /// How long the table lingers on each event when the app's VoiceOver mode is OFF.
    public static func seconds(for payload: RouletteEventPayload) -> Double {
        switch payload {
        case .sessionBegan:   return 0.4
        case .roundBegan:     return 0.5
        case .wheelSpun:      return spinFloor
        case .roundResolved:  return 0.8
        case .roundEnded:     return 0.3
        case .sessionEnded:   return 0.3
        }
    }
}
