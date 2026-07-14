// MachiavelliAudioDirector.swift
// =====================================================================
// The NON-spoken audio consumer for the Machiavelli table (D-072): a parallel
// subscriber to the driver's public event stream that drives the ClockTower's ambient
// MUSIC and makes the bot's long deliberation AUDIBLE.
//
// THE AUDIBLE WAIT (D-072). A bot may deliberate for up to ~15 s. For a blind player,
// that silence reads as a frozen game. So on `botThinkingBegan` the director crossfades
// the erudite classical bed to its more urgent "thinking" passage, and on
// `botThinkingEnded` it returns to calm — a signal on the AMBIENT channel that declares
// "someone is thinking" WITHOUT revealing what they are finding, and WITHOUT ever
// posting a VoiceOver announcement that would interrupt the player's own listening.
//
// It plays no speaker voice and posts no VoiceOver — those SPEAKING systems belong to
// the SpeechConductor / AnnouncementQueue (CONVENTIONS §4). Bot COLOUR voices
// (`vob_clock_*`) are ambient: a missing file falls back to silence, never synthesis
// (D-066). The ambient beds come from the casino palette (D-067), so the ClockTower's
// air is an attribute of the casino.

import Foundation
import GameWorld
import GameEngine
import Audio

/// The three learned archetypes at the ClockTower, for colour-voice selection.
public enum MachiavelliCharacter: Equatable, Sendable { case student, adult, professor }

@MainActor
public final class MachiavelliAudioDirector {

    private let audio: AudioServicing
    private let heroSeatID: Int
    private let characters: [Int: MachiavelliCharacter]
    private let beds: AmbientBeds
    private var rng: SeededGenerator
    private let fastMode: Bool

    private var startedAmbient = false
    private var handNumber = 0
    private var thinking = false
    private var lastColour: SoundID?
    /// The mixing base scale of the main bed (D-080): Machiavelli plays quietest of all —
    /// its long cognitive turn is on the audio channel, so the bed must not compete.
    private var baseScale: Float { beds.bedVolume }

    public init(audio: AudioServicing, heroSeatID: Int, characters: [Int: MachiavelliCharacter],
                beds: AmbientBeds, seed: UInt64, fastMode: Bool = false) {
        self.audio = audio
        self.heroSeatID = heroSeatID
        self.characters = characters
        self.beds = beds
        self.rng = SeededGenerator(seed: seed &* 0x9E37 &+ 0x51)
        self.fastMode = fastMode
    }

    public func run(_ stream: AsyncStream<MachiavelliSessionEvent>) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.consume(stream) }
            if beds.layerIsOccasional { group.addTask { await self.runClockDosing() } }
            await group.next()
            group.cancelAll()
        }
    }

    private func consume(_ stream: AsyncStream<MachiavelliSessionEvent>) async {
        for await event in stream {
            if Task.isCancelled { break }
            handle(event.payload)
        }
    }

    private func handle(_ payload: MachiavelliEventPayload) {
        switch payload {
        case .sessionBegan:
            startAmbientIfNeeded()

        case .handBegan:
            handNumber += 1                     // the music "moves on" to another movement
            if !thinking { crossfadeCalm() }
            audio.play(SoundCatalog.tblShuffle, category: .table)

        case .botThinkingBegan:
            thinking = true
            // The audible wait: shift to the searching passage (D-072).
            audio.crossfadeAmbient(to: bed(beds.tense, beds.tenseFallback), duration: 0.8)

        case .botThinkingEnded:
            thinking = false
            crossfadeCalm()

        case let .tableChanged(seatID, _, placed, rearranged):
            audio.play(rearranged ? SoundCatalog.tblCardFlipSingle : SoundCatalog.tblCardDealSingle, category: .table)
            if seatID != heroSeatID, !placed.isEmpty { maybeColour(seatID, pleased: false) }

        case .playerDrew:
            audio.play(SoundCatalog.tblCardDealSingle, category: .table)

        case let .playerWentOut(seatID):
            if seatID != heroSeatID { maybeColour(seatID, pleased: true) }
            audio.play(seatID == heroSeatID ? SoundCatalog.fxWinHand : SoundCatalog.fxLoseHand, category: .effect)

        case let .matchEnded(winnerID, _, _):
            audio.play(winnerID == heroSeatID ? SoundCatalog.fxVictoryFinal : SoundCatalog.fxDefeatFinal, category: .effect)

        case .sessionEnded:
            break

        default:
            break
        }
    }

    // MARK: - Ambient

    private func startAmbientIfNeeded() {
        guard !startedAmbient else { return }
        startedAmbient = true
        audio.crossfadeAmbient(to: calmMovement, duration: 1.2)
        // The clock is DOSED (occasional) at the ClockTower: start its layer silent and let
        // the dosing task fade it in/out; a continuous-layer casino starts it audibly (D-080).
        if beds.layerIsOccasional {
            audio.startAmbientLayer(bed(beds.layer, beds.layerFallback), volume: 0)
        } else {
            audio.startAmbientLayer(bed(beds.layer, beds.layerFallback), volume: beds.layerVolume)
        }
        audio.setAmbientScale(baseScale, duration: 1.0)   // Machiavelli mixing (D-080)
    }

    /// The calm bed for the current movement, FAVOURING calm_02 in the rotation (D-080).
    private var calmMovement: SoundID {
        ClockAmbientRotation.usesSecondMovement(handNumber)
            ? bed(beds.calm2, beds.calm2Fallback)
            : bed(beds.calm1, beds.calm1Fallback)
    }

    private func crossfadeCalm() {
        audio.crossfadeAmbient(to: calmMovement, duration: 1.0)
    }

    private func bed(_ preferred: SoundID, _ fallback: SoundID) -> SoundID {
        audio.isAvailable(preferred) ? preferred : fallback
    }

    // MARK: - Clock dosing (D-080)

    /// Doses the tower clock in occasional short bursts with long gaps (D-080). Cancelled
    /// when the session's event stream ends.
    private func runClockDosing() async {
        while !Task.isCancelled {
            let (gap, on) = ClockChime.next(using: &rng)
            await sleep(gap)
            if Task.isCancelled { break }
            audio.setAmbientLayerVolume(beds.layerVolume, duration: 1.5)
            await sleep(on)
            audio.setAmbientLayerVolume(0, duration: 2.0)
        }
    }

    private func sleep(_ seconds: Double) async {
        let effective = fastMode ? 0.01 : seconds
        try? await Task.sleep(nanoseconds: UInt64(effective * 1_000_000_000))
    }

    // MARK: - Bot colour (ambient → silence, D-066)

    private func maybeColour(_ seatID: Int, pleased: Bool) {
        guard let character = characters[seatID] else { return }
        // Occasional, deterministic, anti-repetition. Professors comment a little more.
        let chance: Double = pleased ? 0.5 : (character == .professor ? 0.28 : 0.18)
        guard botUnitLocal() < chance else { return }
        let sound = colour(character, pleased: pleased)
        guard sound != lastColour else { return }
        lastColour = sound
        audio.play(sound, category: .botVoice)   // missing file → silence (D-066)
    }

    private func colour(_ character: MachiavelliCharacter, pleased: Bool) -> SoundID {
        switch (character, pleased) {
        case (.student, false):    return SoundCatalog.vobClockStudentEager
        case (.student, true):     return SoundCatalog.vobClockStudentPleased
        case (.adult, false):      return SoundCatalog.vobClockAdultPonders
        case (.adult, true):       return SoundCatalog.vobClockAdultPleased
        case (.professor, false):  return SoundCatalog.vobClockProfessorMasterstroke
        case (.professor, true):   return SoundCatalog.vobClockProfessorPleased
        }
    }

    private func botUnitLocal() -> Double {
        Double(rng.next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
