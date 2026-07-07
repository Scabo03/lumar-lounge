// AudioDirector.swift
// =====================================================================
// The NON-spoken audio consumer (D-029): a parallel subscriber to the driver's
// public stream that plays the physical table sounds and effects (via the pure
// `AudioScore`), drives the DYNAMIC AMBIENT (calm ↔ tense, the showdown hush), and
// speaks the bots' occasional character voicelines (probabilistic, deterministic
// via a seeded generator, never twice in a row for the same bot).
//
// It does NOT play the croupier voice or post VoiceOver — those two SPEAKING
// systems are owned by the `SpeechConductor`, fed by the display consumer. So no
// event is ever voiced by two systems (CONVENTIONS §4).
//
// It paces itself with the same human rhythm as the display so sound stays locked
// to picture; drift resets each hand.

import Foundation
import GameWorld
import GameEngine
import Audio

/// Shared human-pacing between the visual and audio consumers.
enum Pacing {
    static func seconds(for payload: EventPayload) -> Double {
        switch payload {
        case .sessionBegan: return 0.6
        case .handBegan: return 0.8
        case .blindPosted: return 0.45
        case .holeCardsDealt: return 0.2
        case .playerActed: return 0.65
        case .streetOpened: return 0.7
        case .handShown: return 1.0
        case .potAwarded: return 1.2
        case .handEnded: return 1.4
        case .playerBusted: return 1.0
        case .sessionEnded: return 0.0
        default: return 0.3
        }
    }
}

@MainActor
public final class AudioDirector {

    private let audio: AudioServicing
    private let heroSeatID: Int
    private let characters: [Int: BotCharacter]
    private var rng: SeededGenerator
    private let fastMode: Bool

    // Per-hand tracking
    private var handNumber = 0
    private var startChips: [Int: Int] = [:]
    private var stacks: [Int: Int] = [:]
    private var allInInPlay = false
    private var showdownHushed = false
    /// Whether the previous action of a given seat was voiced (anti-repeat).
    private var voicedLastAction: [Int: Bool] = [:]

    public init(audio: AudioServicing, heroSeatID: Int, characters: [Int: BotCharacter],
                seed: UInt64, fastMode: Bool = false) {
        self.audio = audio
        self.heroSeatID = heroSeatID
        self.characters = characters
        self.rng = SeededGenerator(seed: seed)
        self.fastMode = fastMode
    }

    public func run(_ stream: AsyncStream<SessionEvent>) async {
        for await event in stream {
            if Task.isCancelled { break }
            handle(event.payload)
            await pause(Pacing.seconds(for: event.payload))
        }
    }

    /// Processes one event: physical/effect cues (from the pure `AudioScore`) plus
    /// dynamic ambient, hero chip-delta feedback and bot voicelines. Returns the
    /// physical cues (for tests/logging).
    @discardableResult
    public func handle(_ payload: EventPayload) -> [SoundCue] {
        switch payload {
        case let .sessionBegan(seats, _, _):
            audio.startAmbient(SoundCatalog.ambLoungeCalm1)
            audio.startAmbientLayer(SoundCatalog.ambCrowdDistant, volume: 0.2)
            for s in seats { startChips[s.seatID] = s.chips; stacks[s.seatID] = s.chips }

        case let .handBegan(number, _, _, _, _, _, _, seats):
            handNumber = number
            allInInPlay = false
            showdownHushed = false
            voicedLastAction.removeAll()
            for s in seats { startChips[s.seatID] = s.chips; stacks[s.seatID] = s.chips }
            audio.setAmbientScale(1.0, duration: 0.3)
            audio.crossfadeAmbient(to: calmBed(for: number), duration: 0.8)

        case let .blindPosted(seatID, _, amount, _):
            stacks[seatID, default: 0] -= amount

        case let .playerActed(seatID, action):
            handleAction(seatID: seatID, action: action)

        case .handShown:
            hushForShowdown()

        case .potAwarded:
            restoreAmbientAfterShowdown()

        case let .handEnded(_, _, _, _, chips):
            heroChipDeltaFeedback(chips)
            botHandEndVoicelines(chips)
            allInInPlay = false

        case .sessionEnded:
            let heroFinal = stacks[heroSeatID] ?? 0
            audio.play(heroFinal > 0 ? SoundCatalog.fxVictoryFinal : SoundCatalog.fxDefeatFinal, category: .effect)
            audio.stopAll()
            return []

        default:
            break
        }

        let cues = AudioScore.cues(for: payload, heroSeatID: heroSeatID)
        for case let .play(id, category) in cues { audio.play(id, category: category) }
        return cues
    }

    // MARK: - Actions, ambient, bot voices

    private func handleAction(seatID: Int, action: ActedAction) {
        let stackBefore = stacks[seatID] ?? 0
        stacks[seatID, default: 0] -= committed(action)

        if SpeechMap.isAllIn(action), !allInInPlay {
            allInInPlay = true
            audio.crossfadeAmbient(to: SoundCatalog.ambLoungeTense, duration: 0.8)
        }
        if seatID != heroSeatID, let voice = botVoice(seatID: seatID, action: action, stackBefore: stackBefore) {
            audio.play(voice, category: .botVoice)
        }
    }

    private func hushForShowdown() {
        guard !showdownHushed else { return }
        showdownHushed = true
        audio.setAmbientScale(0.35, duration: 0.5)
        audio.play(SoundCatalog.ambSilenceTension, category: .ambient)
    }

    private func restoreAmbientAfterShowdown() {
        guard showdownHushed || allInInPlay else { return }
        showdownHushed = false
        audio.setAmbientScale(1.0, duration: 0.5)
        if allInInPlay { audio.crossfadeAmbient(to: calmBed(for: handNumber), duration: 1.0) }
    }

    /// The hero's per-hand win/lose/neutral sting, from the chip delta.
    private func heroChipDeltaFeedback(_ chips: [Int: Int]) {
        guard let start = startChips[heroSeatID], let final = chips[heroSeatID] else { return }
        let fx = final > start ? SoundCatalog.fxWinHand
               : (final < start ? SoundCatalog.fxLoseHand : SoundCatalog.fxHandNeutral)
        audio.play(fx, category: .effect)
        stacks[heroSeatID] = final
    }

    /// The novice reacts emotionally to winning/losing a hand (the others don't).
    private func botHandEndVoicelines(_ chips: [Int: Int]) {
        for (seat, character) in characters where character == .novice {
            guard let start = startChips[seat], let final = chips[seat] else { continue }
            stacks[seat] = final
            if final > start, roll() < 0.5 {
                audio.play(SoundCatalog.vobNoviceExcited, category: .botVoice)
            } else if final < start, roll() < 0.4 {
                audio.play(SoundCatalog.vobNoviceDisappointed, category: .botVoice)
            }
        }
    }

    /// Picks a bot voiceline for an action, honouring the per-character rules, the
    /// probabilities, and the "never twice in a row for the same bot" guard.
    private func botVoice(seatID: Int, action: ActedAction, stackBefore: Int) -> SoundID? {
        guard let character = characters[seatID] else { return nil }
        // Anti-repeat: if this bot's previous action spoke, this one stays silent.
        if voicedLastAction[seatID] == true { voicedLastAction[seatID] = false; return nil }

        let (candidate, probability) = candidate(for: character, action: action, stackBefore: stackBefore)
        guard let candidate, roll() < probability else {
            voicedLastAction[seatID] = false
            return nil
        }
        voicedLastAction[seatID] = true
        return candidate
    }

    private func candidate(for character: BotCharacter, action: ActedAction, stackBefore: Int) -> (SoundID?, Double) {
        let allIn = SpeechMap.isAllIn(action)
        switch character {
        case .novice:
            switch action {
            case .bet, .raised:
                // Excited after an aggressive move of its own (all-in has its own cue).
                return allIn ? (nil, 0) : (SoundCatalog.vobNoviceExcited, 0.22)
            case let .called(amount, isAllIn):
                // Nervous before a big call (large relative to its stack).
                let big = !isAllIn && stackBefore > 0 && Double(amount) > 0.25 * Double(stackBefore)
                return big ? (SoundCatalog.vobNoviceNervous, 0.22) : (nil, 0)
            default:
                return (nil, 0)
            }
        case .rock:
            // Taciturn: a rare neutral grunt on any of its actions.
            return (SoundCatalog.vobRockGrunt, 0.10)
        case .aggressor:
            switch action {
            case .bet, .raised:
                guard !allIn else { return (nil, 0) }
                // Mostly confident, occasionally a taunt.
                return (roll() < 0.25 ? SoundCatalog.vobAggressorTaunt : SoundCatalog.vobAggressorConfident, 0.22)
            default:
                return (nil, 0)
            }
        }
    }

    // MARK: - Helpers

    private func calmBed(for handNumber: Int) -> SoundID {
        handNumber % 2 == 0 ? SoundCatalog.ambLoungeCalm1 : SoundCatalog.ambLoungeCalm2
    }

    private func committed(_ action: ActedAction) -> Int {
        switch action {
        case .folded, .checked: return 0
        case let .called(amount, _): return amount
        case let .bet(_, amount, _), let .raised(_, amount, _): return amount
        }
    }

    /// A uniform Double in [0, 1) from the seeded generator.
    private func roll() -> Double {
        Double(rng.next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    private func pause(_ seconds: Double) async {
        let effective = fastMode ? 0.01 : seconds
        guard effective > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(effective * 1_000_000_000))
    }
}
