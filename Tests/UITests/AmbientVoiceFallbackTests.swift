import XCTest
@testable import UI
import Audio

/// The informative-vs-ambient voice distinction (D-066): a SPOKEN voice whose mp3
/// isn't bundled falls back to VoiceOver SYNTHESIS if it is INFORMATIVE (croupier),
/// but to SILENCE if it is AMBIENT (bot colour). A missing colour line must never
/// become an intrusive announcement.
@MainActor
final class AmbientVoiceFallbackTests: XCTestCase {

    private func makeRig() -> (RecordingAudioService, SpeechConductor, () -> [String]) {
        let audio = RecordingAudioService()
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = false
        var synths: [String] = []
        queue.synthesisObserver = { synths.append($0) }
        return (audio, SpeechConductor(audio: audio, queue: queue), { synths })
    }
    private func drain() async { try? await Task.sleep(nanoseconds: 150_000_000) }

    func testAmbientVoiceMissingMp3FallsBackToSilenceNotSynthesis() async {
        let (audio, conductor, synths) = makeRig()
        // A Skypool urban colour line, not produced yet, WITH a declared fallback text.
        audio.missing = [SoundCatalog.vobSkyAggressorTaunt.rawValue]
        conductor.say(lead: SoundCatalog.vobSkyAggressorTaunt, leadCategory: .botVoice,
                      fallback: "colore ambientale", priority: .medium)
        await drain()
        XCTAssertTrue(audio.log.isEmpty, "the missing colour mp3 must not play")
        XCTAssertTrue(synths().isEmpty, "an AMBIENT voice must NOT synthesise its fallback (silence)")
    }

    func testInformativeVoiceMissingMp3FallsBackToSynthesis() async {
        let (audio, conductor, synths) = makeRig()
        // A Skypool croupier (informative) line, not produced yet, with a fallback.
        audio.missing = [SoundCatalog.voSkyRoleButton.rawValue]
        conductor.say(lead: SoundCatalog.voSkyRoleButton, leadCategory: .croupier,
                      fallback: "sei sul bàtton", priority: .high)
        await drain()
        XCTAssertTrue(audio.log.isEmpty)
        XCTAssertEqual(synths(), ["sei sul bàtton"], "an INFORMATIVE voice speaks its fallback")
    }

    func testCategoryFallbackPolicyIsDeclaredOnTheCategory() {
        // The rule lives on the category, so every future voice inherits it (D-066).
        XCTAssertTrue(SoundCategory.croupier.fallsBackToSynthesis)
        XCTAssertFalse(SoundCategory.botVoice.fallsBackToSynthesis)
    }
}
