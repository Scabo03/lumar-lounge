// AudioScore.swift
// =====================================================================
// The event → sounds mapping (D-023): a PURE function that turns a public
// `SessionEvent` payload into the sound cues to play. It lives in UI — the only
// layer that sees both `SessionEvent` (via GameWorld) and the `Audio` module —
// so the `Audio` module itself stays game-agnostic. Like `TableAnnouncer`
// (event → speech), this is pure and unit-testable, separate from playback.
//
// Bot voices are PROBABILISTIC: not every action speaks. The randomness is a
// seeded generator passed in, so the mapping stays deterministic and testable.

import Foundation
import GameWorld
import GameEngine
import Audio

/// One thing to do to the audio engine.
public enum SoundCue: Equatable, Sendable {
    case startAmbient(SoundID)
    case play(SoundID, SoundCategory)
}

/// The two spoken lines a bot can utter, chosen by its personality's catalog.
public struct BotVoiceProfile: Equatable, Sendable {
    public let confident: SoundID
    public let disappointed: SoundID
    public init(confident: SoundID, disappointed: SoundID) {
        self.confident = confident
        self.disappointed = disappointed
    }
}

public enum AudioScore {

    /// The sound cues for one event. Pure: identical inputs (including the RNG
    /// state) give identical cues.
    public static func cues(for payload: EventPayload,
                            heroSeatID: Int,
                            voices: [Int: BotVoiceProfile],
                            rng: inout SeededGenerator) -> [SoundCue] {
        switch payload {

        case .sessionBegan:
            return [.startAmbient(SoundCatalog.ambientLounge)]

        case .holeCardsDealt:
            return [.play(SoundCatalog.cardDeal, .table)]

        case .blindPosted:
            return [.play(SoundCatalog.chipsBet, .table)]

        case let .playerActed(seatID, action):
            return actionCues(seatID: seatID, action: action,
                              heroSeatID: heroSeatID, voices: voices, rng: &rng)

        case let .streetOpened(street, _):
            switch street {
            case .flop:  return [.play(SoundCatalog.cardFlip, .table), .play(SoundCatalog.voFlop, .croupier)]
            case .turn:  return [.play(SoundCatalog.cardFlip, .table), .play(SoundCatalog.voTurn, .croupier)]
            case .river: return [.play(SoundCatalog.cardFlip, .table), .play(SoundCatalog.voRiver, .croupier)]
            case .preflop: return []
            }

        case let .potAwarded(_, _, winnerSeatIDs):
            if winnerSeatIDs.contains(heroSeatID) {
                return [.play(SoundCatalog.fxWinHand, .effect)]
            }
            var cues: [SoundCue] = [.play(SoundCatalog.chipsToPot, .table)]
            if let botWinner = winnerSeatIDs.first(where: { voices[$0] != nil }),
               let profile = voices[botWinner], roll(&rng) < 0.4 {
                cues.append(.play(profile.confident, .botVoice))
            }
            return cues

        case let .playerBusted(playerID):
            if let profile = voices[playerID], roll(&rng) < 0.6 {
                return [.play(profile.disappointed, .botVoice)]
            }
            return []

        // Handled elsewhere or intentionally silent:
        case .handShown, .handEnded, .sessionEnded, .privateHoleCards,
             .handBegan, .playerJoined, .playerLeft:
            return []
        }
    }

    private static func actionCues(seatID: Int, action: ActedAction,
                                   heroSeatID: Int, voices: [Int: BotVoiceProfile],
                                   rng: inout SeededGenerator) -> [SoundCue] {
        switch action {
        case .folded:
            return [.play(SoundCatalog.cardMuck, .table)]
        case .checked:
            return []
        case let .called(_, isAllIn):
            return chipsAndMaybeAllIn(isAllIn: isAllIn)
        case let .bet(_, _, isAllIn), let .raised(_, _, isAllIn):
            var cues = chipsAndMaybeAllIn(isAllIn: isAllIn)
            // An aggressive bot occasionally talks it up.
            if let profile = voices[seatID], seatID != heroSeatID, roll(&rng) < 0.35 {
                cues.append(.play(profile.confident, .botVoice))
            }
            return cues
        }
    }

    private static func chipsAndMaybeAllIn(isAllIn: Bool) -> [SoundCue] {
        var cues: [SoundCue] = [.play(SoundCatalog.chipsBet, .table)]
        if isAllIn {
            cues.append(.play(SoundCatalog.voAllIn, .croupier))
            cues.append(.play(SoundCatalog.fxAllInDramatic, .effect))
        }
        return cues
    }

    /// A uniform Double in [0, 1) from the seeded generator.
    private static func roll(_ rng: inout SeededGenerator) -> Double {
        Double(rng.next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
