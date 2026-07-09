// DrawBotChatter.swift
// =====================================================================
// Decides a bot's occasional colour voiceline (vob_) for a draw-table ACTION —
// the draw analogue of the Texas `BotChatter` (D-031). Lives on the display side
// so present() can hand it to the `SpeechConductor` as the LEAD before the action
// synthesis: the vob_ (emotional colour) plays first, then "giocatore N rilancia".
// Deterministic (seeded), same low probabilities and "never twice in a row" guard.

import Foundation
import GameWorld
import GameEngine
import Audio

@MainActor
final class DrawBotChatter {

    private let heroSeatID: Int
    private let characters: [Int: BotCharacter]
    private var rng: SeededGenerator
    private var stacks: [Int: Int] = [:]
    private var voicedLastAction: [Int: Bool] = [:]

    init(heroSeatID: Int, characters: [Int: BotCharacter], seed: UInt64) {
        self.heroSeatID = heroSeatID
        self.characters = characters
        self.rng = SeededGenerator(seed: seed)
    }

    func handBegan(seats: [DrawSeatSnapshot]) {
        for s in seats { stacks[s.seatID] = s.chips }
        voicedLastAction.removeAll()
    }

    /// The colour voiceline for an opponent's (non-all-in) action, or nil.
    func actionVoice(seat: Int, action: DrawActedAction) -> SoundID? {
        let stackBefore = stacks[seat] ?? 0
        stacks[seat, default: 0] -= committed(action)
        guard seat != heroSeatID, let character = characters[seat] else { return nil }
        if voicedLastAction[seat] == true { voicedLastAction[seat] = false; return nil }

        let (candidate, probability) = candidate(for: character, action: action, stackBefore: stackBefore)
        guard let candidate, roll() < probability else {
            voicedLastAction[seat] = false
            return nil
        }
        voicedLastAction[seat] = true
        return candidate
    }

    private func candidate(for character: BotCharacter, action: DrawActedAction, stackBefore: Int) -> (SoundID?, Double) {
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

    private func committed(_ action: DrawActedAction) -> Int {
        switch action {
        case .folded, .checked: return 0
        case let .called(amount, _): return amount
        case let .bet(amount, _), let .raised(amount, _): return amount
        }
    }

    private func roll() -> Double {
        Double(rng.next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
