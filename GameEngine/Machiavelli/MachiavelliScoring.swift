// MachiavelliScoring.swift
// =====================================================================
// THE HAND SCORING of Machiavelli (D-071) — pure game logic, so it lives in the
// engine, never in the driver. A single hand ends when a player goes out; at that
// moment every player is scored from the FINAL state of the hand:
//
//   • the player who went out earns a flat OUT BONUS;
//   • everyone earns points for the value they PLACED on the table this hand;
//   • everyone is penalised for the value LEFT in their hand.
//
// The card-value scale is IMPOSED (D-071): ace = 10, figures (J/Q/K) = 5, numbered
// cards (2–10) = 1. The out bonus, the placed/remaining weights and the MATCH victory
// threshold are engineering choices (see D-071); the threshold and the match structure
// itself are a SESSION mechanic and live in GameWorld, not here — this file only
// computes the points of ONE hand from its final state.
//
// Why scoring exists (game design, not just length): it gives a purpose to a player
// who is NOT winning the hand. Every card laid down before an opponent closes counts,
// and every card stranded in hand hurts — so there is always something to do, and a
// real tension between dumping now to limit the damage and holding to build something
// bigger. See D-071.
//
// Foundation only.

import Foundation

public enum MachiavelliScoring {

    // MARK: - The imposed card-value scale (D-071)

    /// The point value of a card: ace 10, figure (J/Q/K) 5, numbered (2–10) 1.
    public static func cardValue(_ card: Card) -> Int {
        switch card.rank {
        case .ace:                 return 10
        case .jack, .queen, .king: return 5
        default:                   return 1
        }
    }

    /// The total point value of a set of cards.
    public static func handValue(_ cards: [Card]) -> Int {
        cards.reduce(0) { $0 + cardValue($1) }
    }

    // MARK: - Tunable weights (D-071)

    /// Flat reward for going out. Chosen ≈ two aces' worth: closing is a real
    /// achievement, but not so large that placing value stops mattering (D-071).
    public static let outBonus = 20
    /// Weight on the value a player PLACED on the table this hand.
    public static let placedWeight = 1
    /// Weight on the value LEFT in a player's hand. Equal to `placedWeight`, so a card
    /// you started with swings 2× its value between placing and holding it — enough
    /// tension to make dumping matter, without drowning the out bonus (D-071).
    public static let remainingWeight = 1

    // MARK: - Per-hand scoring (pure)

    /// One player's contribution to a hand, as tracked by the driver.
    public struct PlayerHandResult: Equatable, Sendable {
        public let playerID: Int
        /// The cards this player laid onto the table during the hand.
        public let placed: [Card]
        /// The cards still in this player's hand when the hand ended.
        public let remaining: [Card]
        /// Whether this player went out (emptied their hand).
        public let wentOut: Bool

        public init(playerID: Int, placed: [Card], remaining: [Card], wentOut: Bool) {
            self.playerID = playerID
            self.placed = placed
            self.remaining = remaining
            self.wentOut = wentOut
        }
    }

    /// The points a single player earns this hand.
    public static func score(_ result: PlayerHandResult) -> Int {
        (result.wentOut ? outBonus : 0)
            + placedWeight * handValue(result.placed)
            - remainingWeight * handValue(result.remaining)
    }

    /// The points every player earns this hand, keyed by player id.
    public static func score(_ results: [PlayerHandResult]) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: results.map { ($0.playerID, score($0)) })
    }
}
