// AudioDirector.swift
// =====================================================================
// The NON-spoken audio consumer (D-029): a parallel subscriber to the driver's
// public stream that plays the physical table sounds and effects (via the pure
// `AudioScore`), drives the DYNAMIC AMBIENT (calm ↔ tense, the showdown hush), and
// plays the bots' hand-END reactions (novice win/lose). The bots' ACTION colour
// voicelines moved to `BotChatter` + the conductor so they can be ordered before
// the action synthesis (D-031).
//
// It plays no croupier voice and posts no VoiceOver — those SPEAKING systems are
// the `SpeechConductor`'s (CONVENTIONS §4). It paces itself with the same rhythm
// as the display so sound stays locked to picture; drift resets each hand.

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

    private var handNumber = 0
    private var startChips: [Int: Int] = [:]
    private var heroChips = 0
    private var allInInPlay = false
    private var showdownHushed = false
    /// The seats actually PLAYING the current hand (from `handBegan`), and the seats
    /// that have BUSTED. A bot's voiceline is only ever chosen for a seat that is
    /// alive AND in the current hand — never a snapshot from the start of the session
    /// (D-058). This is what keeps an eliminated bot from speaking in later hands:
    /// `handEnded.chips` still lists busted seats (with 0), while `handBegan.seats`
    /// does not, so filtering on the live set is the fix.
    private var activeSeats: Set<Int> = []
    private var bustedSeats: Set<Int> = []
    /// The table's base big blind; a hand whose blind exceeds it is decisive (D-037).
    private let baseBigBlind: Int

    public init(audio: AudioServicing, heroSeatID: Int, characters: [Int: BotCharacter],
                seed: UInt64, fastMode: Bool = false, baseBigBlind: Int = 20) {
        self.audio = audio
        self.heroSeatID = heroSeatID
        self.characters = characters
        self.rng = SeededGenerator(seed: seed)
        self.fastMode = fastMode
        self.baseBigBlind = baseBigBlind
    }

    public func run(_ stream: AsyncStream<SessionEvent>) async {
        for await event in stream {
            if Task.isCancelled { break }
            handle(event.payload)
            await pause(Pacing.seconds(for: event.payload))
        }
    }

    /// Processes one event: physical/effect cues (pure `AudioScore`) plus dynamic
    /// ambient, hero chip-delta feedback and bots' hand-end reactions. Returns the
    /// physical cues (for tests/logging).
    @discardableResult
    public func handle(_ payload: EventPayload) -> [SoundCue] {
        switch payload {
        case let .sessionBegan(seats, _, _):
            audio.startAmbient(SoundCatalog.ambLoungeCalm1)
            audio.startAmbientLayer(SoundCatalog.ambCrowdDistant, volume: 0.2)
            for s in seats { startChips[s.seatID] = s.chips }
            heroChips = startChips[heroSeatID] ?? 0

        case let .handBegan(number, _, _, _, _, _, bigBlind, seats):
            handNumber = number
            allInInPlay = false
            showdownHushed = false
            activeSeats = Set(seats.map { $0.seatID })   // only these play this hand (D-058)
            for s in seats { startChips[s.seatID] = s.chips }
            audio.setAmbientScale(1.0, duration: 0.3)
            // A decisive hand (doubled blinds) opens on the tense bed (D-037).
            let bed = bigBlind > baseBigBlind ? SoundCatalog.ambLoungeTense : calmBed(for: number)
            audio.crossfadeAmbient(to: bed, duration: 0.8)

        case let .playerActed(_, action):
            if SpeechMap.isAllIn(action), !allInInPlay {
                allInInPlay = true
                audio.crossfadeAmbient(to: SoundCatalog.ambLoungeTense, duration: 0.8)
            }

        case .handShown:
            hushForShowdown()

        case .potAwarded:
            restoreAmbientAfterShowdown()

        case let .handEnded(_, _, _, _, chips):
            heroChipDeltaFeedback(chips)
            botHandEndVoicelines(chips)
            allInInPlay = false

        case let .playerBusted(playerID):
            bustedSeats.insert(playerID)   // never voice this seat again (D-058)

        case .sessionEnded:
            audio.play(heroChips > 0 ? SoundCatalog.fxVictoryFinal : SoundCatalog.fxDefeatFinal, category: .effect)
            audio.stopAll()
            return []

        default:
            break
        }

        let cues = AudioScore.cues(for: payload, heroSeatID: heroSeatID)
        for case let .play(id, category) in cues { audio.play(id, category: category) }
        return cues
    }

    // MARK: - Ambient + feedback

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

    private func heroChipDeltaFeedback(_ chips: [Int: Int]) {
        guard let start = startChips[heroSeatID], let final = chips[heroSeatID] else { return }
        let fx = final > start ? SoundCatalog.fxWinHand
               : (final < start ? SoundCatalog.fxLoseHand : SoundCatalog.fxHandNeutral)
        audio.play(fx, category: .effect)
        heroChips = final
    }

    /// The novice reacts emotionally to winning/losing a hand (the others don't).
    /// Only for a seat that actually PLAYED this hand and hasn't busted — a snapshot
    /// of the seats would keep an eliminated bot reacting forever (D-058).
    private func botHandEndVoicelines(_ chips: [Int: Int]) {
        for (seat, character) in characters
        where character == .novice && activeSeats.contains(seat) && !bustedSeats.contains(seat) {
            guard let start = startChips[seat], let final = chips[seat] else { continue }
            if final > start, roll() < 0.5 {
                audio.play(SoundCatalog.vobNoviceExcited, category: .botVoice)
            } else if final < start, roll() < 0.4 {
                audio.play(SoundCatalog.vobNoviceDisappointed, category: .botVoice)
            }
        }
    }

    private func calmBed(for handNumber: Int) -> SoundID {
        handNumber % 2 == 0 ? SoundCatalog.ambLoungeCalm1 : SoundCatalog.ambLoungeCalm2
    }

    private func roll() -> Double {
        Double(rng.next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    private func pause(_ seconds: Double) async {
        let effective = fastMode ? 0.01 : seconds
        guard effective > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(effective * 1_000_000_000))
    }
}
