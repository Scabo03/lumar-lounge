// RouletteTableState.swift
// =====================================================================
// The pure, event-derived DISPLAY state of a roulette table (D-103): what the
// wheel and the wallet show. No SwiftUI, no game logic — a reduction of events
// into a value, unit-testable with swift test (D-017).
//
// The BETS the player is composing are NOT here: they live in the single-source
// `RouletteBetSlip` the view model owns and both zones edit (D-102). This state
// is only the things the SESSION narrates — chips, phase, the last spin's result.

import Foundation
import GameEngine
import GameWorld

/// Where the round is, so the view knows whether to show the betting surface, the
/// spinning wait, or the settled result.
public enum RoulettePhase: Equatable, Sendable {
    case betting        // composing the slip
    case spinning       // confirmed; the wheel is turning
    case resolved       // the spin is settled and being shown
    case ended          // the session is over
}

public struct RouletteTableState: Equatable, Sendable {
    public var chips: Int
    public var minimumBet: Int
    public var maximumBet: Int
    public var roundNumber: Int
    public var phase: RoulettePhase

    /// The last settled spin, for the felt to show the number/colour and the result.
    public var lastResolution: RouletteRoundResolution?

    public init(chips: Int = 0, minimumBet: Int = 0, maximumBet: Int = 0,
                roundNumber: Int = 0, phase: RoulettePhase = .betting,
                lastResolution: RouletteRoundResolution? = nil) {
        self.chips = chips
        self.minimumBet = minimumBet
        self.maximumBet = maximumBet
        self.roundNumber = roundNumber
        self.phase = phase
        self.lastResolution = lastResolution
    }

    public var lastPocket: Int? { lastResolution?.winningPocket }
    public var lastColor: RouletteColor? { lastResolution?.color }
}

public enum RouletteTableReducer {
    public static func reduce(_ state: RouletteTableState, _ payload: RouletteEventPayload) -> RouletteTableState {
        var next = state
        switch payload {
        case let .sessionBegan(chips, minimumBet, maximumBet):
            next.chips = chips
            next.minimumBet = minimumBet
            next.maximumBet = maximumBet

        case let .roundBegan(roundNumber, _, chips):
            next.roundNumber = roundNumber
            next.chips = chips
            next.phase = .spinning
            next.lastResolution = nil

        case .wheelSpun:
            next.phase = .spinning

        case let .roundResolved(resolution, chips):
            next.chips = chips
            next.lastResolution = resolution
            next.phase = .resolved

        case let .roundEnded(_, _, chips):
            next.chips = chips

        case .sessionEnded:
            next.phase = .ended
        }
        return next
    }
}
