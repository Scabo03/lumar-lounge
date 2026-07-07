import XCTest
@testable import UI
import Audio

/// The serial speech owner (D-029). The key regression: the pot voice must play
/// at most once per hand even when several `potAwarded` events (side pots) arrive
/// — the "broken record" bug.
@MainActor
final class SpeechConductorTests: XCTestCase {

    private func drain() async {
        try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms: let the serial queue run
    }

    func testPotVoicePlaysOncePerHandAcrossSidePots() async {
        let audio = RecordingAudioService()
        let conductor = SpeechConductor(audio: audio, announcer: Announcer())
        conductor.handBegan()
        // A multiway all-in resolves into a main pot + two side pots: three events.
        conductor.say(croupier: SoundCatalog.voPotAwarded, synthesis: nil)
        conductor.say(croupier: SoundCatalog.voPotAwarded, synthesis: nil)
        conductor.say(croupier: SoundCatalog.voPotAwarded, synthesis: nil)
        await drain()
        XCTAssertEqual(audio.log.filter { $0.id == SoundCatalog.voPotAwarded }.count, 1,
                       "pot-awarded voice must play exactly once per hand")
    }

    func testShowdownVoicePlaysOncePerHandAcrossReveals() async {
        let audio = RecordingAudioService()
        let conductor = SpeechConductor(audio: audio, announcer: Announcer())
        conductor.handBegan()
        conductor.say(croupier: SoundCatalog.voShowdown, synthesis: nil)
        conductor.say(croupier: SoundCatalog.voShowdown, synthesis: nil)
        await drain()
        XCTAssertEqual(audio.log.filter { $0.id == SoundCatalog.voShowdown }.count, 1)
    }

    func testOncePerHandVoiceResetsOnTheNextHand() async {
        let audio = RecordingAudioService()
        let conductor = SpeechConductor(audio: audio, announcer: Announcer())
        conductor.handBegan(); conductor.say(croupier: SoundCatalog.voPotAwarded, synthesis: nil)
        conductor.handBegan(); conductor.say(croupier: SoundCatalog.voPotAwarded, synthesis: nil)
        await drain()
        XCTAssertEqual(audio.log.filter { $0.id == SoundCatalog.voPotAwarded }.count, 2)
    }

    func testOrdinaryCroupierLinesAreNotDeduped() async {
        let audio = RecordingAudioService()
        let conductor = SpeechConductor(audio: audio, announcer: Announcer())
        conductor.handBegan()
        conductor.say(croupier: SoundCatalog.voFlop, synthesis: nil)
        conductor.say(croupier: SoundCatalog.voTurn, synthesis: nil)
        conductor.say(croupier: SoundCatalog.voFlop, synthesis: nil) // (contrived) not once-per-hand
        await drain()
        XCTAssertEqual(audio.log.filter { $0.category == .croupier }.count, 3)
    }
}
