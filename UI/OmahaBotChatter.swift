// OmahaBotChatter.swift
// =====================================================================
// Decides a Skypool bot's occasional colour voiceline (vob_sky_*) for an Omaha ACTION
// — the Omaha analogue of the Texas/Draw `BotChatter` (D-031). Lives on the display
// side so present() can hand it to the `SpeechConductor` as the LEAD before the action
// synthesis: the vob_ (emotional colour) plays first, then "giocatore N rilancia".
//
// These colour lines are AMBIENT (D-066): the vob_sky_* files aren't produced yet, so
// with the informative/ambient fallback rule the conductor plays them as SILENCE — a
// missing colour line simply doesn't sound, never a synthesised announcement. The
// chatter still runs (deterministic, "never twice in a row") so it wires up cleanly
// the moment the urban voices are delivered.

import Foundation
import GameWorld
import GameEngine
import Audio

@MainActor
final class OmahaBotChatter {

    private let heroSeatID: Int
    private let characters: [Int: BotCharacter]
    private var rng: SeededGenerator
    private var stacks: [Int: Int] = [:]
    private var activeSeats: Set<Int> = []
    private var voicedLastAction: [Int: Bool] = [:]
    /// The hosting casino's bot colour voices (D-067); default the Skypool urban set.
    private let voices: BotVoices

    init(heroSeatID: Int, characters: [Int: BotCharacter], seed: UInt64, voices: BotVoices = .skypool) {
        self.heroSeatID = heroSeatID
        self.characters = characters
        self.rng = SeededGenerator(seed: seed)
        self.voices = voices
    }

    func handBegan(seats: [OmahaSeatSnapshot]) {
        for s in seats { stacks[s.seatID] = s.chips }
        activeSeats = Set(seats.map { $0.seatID })
        voicedLastAction.removeAll()
    }

    /// The Skypool colour voiceline for an opponent's (non-all-in) action, or nil.
    func actionVoice(seat: Int, action: OmahaActedAction) -> SoundID? {
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

    private func candidate(for character: BotCharacter, action: OmahaActedAction, stackBefore: Int) -> (SoundID?, Double) {
        switch character {
        case .novice:
            switch action {
            case .bet, .raised:
                return (voices.noviceExcited, 0.22)
            case let .called(amount, _):
                let big = stackBefore > 0 && Double(amount) > 0.25 * Double(stackBefore)
                return big ? (voices.noviceNervous, 0.22) : (nil, 0)
            default:
                return (nil, 0)
            }
        case .rock:
            return (voices.rockGrunt, 0.10)
        case .aggressor:
            switch action {
            case .bet, .raised:
                // One roll for the flavour (RNG stream unchanged): an occasional
                // bluff-giveaway tell (D-068), else taunt, else confidence.
                let r = roll()
                let voice = r < 0.15 ? voices.aggressorBluffGiveaway
                          : (r < 0.40 ? voices.aggressorTaunt : voices.aggressorConfident)
                return (voice, 0.22)
            default:
                return (nil, 0)
            }
        }
    }

    private func committed(_ action: OmahaActedAction) -> Int {
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
