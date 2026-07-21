// RouletteAudioScore.swift
// =====================================================================
// The pacing of a roulette table (D-103), and the physical sounds it plays.
//
// Roulette is a FAST game — bet, spin, collect, again — so the beats are short,
// the same brisk rhythm blackjack keeps (D-091). The one beat that matters is the
// SPIN WAIT, handled with care because there is no wheel mp3 yet (see the view
// model): its floor is deliberately short so the wait is never a long silence,
// and it is structured so the real wheel sound slots straight in without teardown.

import Foundation
import Audio
import GameWorld

public enum RoulettePacing {

    /// The felt interval the wheel "turns" for when NO wheel mp3 is bundled — short, so
    /// the wait is a beat, never a disorienting silent freeze (D-103). When the real
    /// `fx_roulette_wheel_spin.mp3` is cabled, the wait grows to ITS duration instead
    /// (the view model uses `audio.duration(of:) ?? spinFloor`), so the sound takes the
    /// place of the fill with no change to the logic.
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
