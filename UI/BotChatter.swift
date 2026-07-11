// BotChatter.swift
// =====================================================================
// Decides a bot's occasional colour voiceline (vob_) for an ACTION (D-031). Lives
// on the display side so present() can hand it to the `SpeechConductor` as the
// lead BEFORE the action's synthesis — the vob_ (emotional colour) plays first,
// then the precise "player N raises to X". Deterministic (seeded), with the
// per-character rules, the low probabilities, and the "never twice in a row for
// the same bot" guard.
//
// The bots' hand-end reactions (novice win/lose) stay in `AudioDirector`; those
// need no ordering with a synthesis. Probabilities are intentionally low — the
// acoustic gap is filled by the action SYNTHESES, not by more vob_.

import Foundation
import GameWorld
import GameEngine
import Audio

@MainActor
final class BotChatter {

    private let heroSeatID: Int
    private let characters: [Int: BotCharacter]
    private var rng: SeededGenerator
    private var stacks: [Int: Int] = [:]
    /// The seats playing the CURRENT hand (from `handBegan`). A voiceline is only
    /// chosen for a seat in this live set, so an eliminated bot — absent from later
    /// `handBegan.seats` — is never voiced (D-058).
    private var activeSeats: Set<Int> = []
    /// Whether a seat's previous action was voiced (anti-repeat).
    private var voicedLastAction: [Int: Bool] = [:]

    init(heroSeatID: Int, characters: [Int: BotCharacter], seed: UInt64) {
        self.heroSeatID = heroSeatID
        self.characters = characters
        self.rng = SeededGenerator(seed: seed)
    }

    func handBegan(seats: [SeatSnapshot]) {
        for s in seats { stacks[s.seatID] = s.chips }
        activeSeats = Set(seats.map { $0.seatID })
        voicedLastAction.removeAll()
    }

    /// The colour voiceline for an opponent's (non-all-in) action, or nil. Updates
    /// the stack tracking and the anti-repeat state.
    func actionVoice(seat: Int, action: ActedAction) -> SoundID? {
        let stackBefore = stacks[seat] ?? 0
        stacks[seat, default: 0] -= committed(action)
        guard seat != heroSeatID, activeSeats.contains(seat), let character = characters[seat] else { return nil }
        if voicedLastAction[seat] == true { voicedLastAction[seat] = false; return nil }

        let (candidate, probability) = candidate(for: character, action: action, stackBefore: stackBefore)
        guard let candidate, roll() < probability else {
            voicedLastAction[seat] = false
            return nil
        }
        voicedLastAction[seat] = true
        return candidate
    }

    private func candidate(for character: BotCharacter, action: ActedAction, stackBefore: Int) -> (SoundID?, Double) {
        switch character {
        case .novice:
            switch action {
            case .bet, .raised:
                return (SoundCatalog.vobNoviceExcited, 0.22)
            case let .called(amount, _):
                let big = stackBefore > 0 && Double(amount) > 0.25 * Double(stackBefore)
                return big ? (SoundCatalog.vobNoviceNervous, 0.22) : (nil, 0)
            default:
                return (nil, 0)
            }
        case .rock:
            return (SoundCatalog.vobRockGrunt, 0.10)
        case .aggressor:
            switch action {
            case .bet, .raised:
                return (roll() < 0.25 ? SoundCatalog.vobAggressorTaunt : SoundCatalog.vobAggressorConfident, 0.22)
            default:
                return (nil, 0)
            }
        }
    }

    private func committed(_ action: ActedAction) -> Int {
        switch action {
        case .folded, .checked: return 0
        case let .called(amount, _): return amount
        case let .bet(_, amount, _), let .raised(_, amount, _): return amount
        }
    }

    private func roll() -> Double {
        Double(rng.next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
