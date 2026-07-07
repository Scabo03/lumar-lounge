import XCTest
@testable import UI
import Audio

/// The poker narration director on top of the shared `AnnouncementQueue`
/// (D-029..D-032): once-per-hand de-dup, mp3→synthesis fallback, lead→synthesis
/// ordering, and the time-critical turn. Croupier mp3s land on the audio recorder;
/// synthesis lands on the queue's observer.
@MainActor
final class SpeechConductorTests: XCTestCase {

    private func makeRig() -> (RecordingAudioService, AnnouncementQueue, SpeechConductor, () -> [String]) {
        let audio = RecordingAudioService()
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = false   // host: no VoiceOver → synchronous, observer still fires
        var synths: [String] = []
        queue.synthesisObserver = { synths.append($0) }
        let conductor = SpeechConductor(audio: audio, queue: queue)
        return (audio, queue, conductor, { synths })
    }

    private func drain() async { try? await Task.sleep(nanoseconds: 150_000_000) }

    // MARK: - Pot "broken record" (once per hand)

    func testPotMp3PlaysOncePerHandAcrossSidePots() async {
        let (audio, _, conductor, _) = makeRig()
        conductor.handBegan()
        conductor.say(lead: SoundCatalog.voPotAwarded)
        conductor.say(lead: SoundCatalog.voPotAwarded)
        conductor.say(lead: SoundCatalog.voPotAwarded)
        await drain()
        XCTAssertEqual(audio.log.filter { $0.id == SoundCatalog.voPotAwarded }.count, 1)
    }

    func testShowdownVoicePlaysOncePerHandButEachRevealIsSynthesized() async {
        let (audio, _, conductor, synths) = makeRig()
        conductor.handBegan()
        conductor.say(lead: SoundCatalog.voShowdown, synthesis: "player 1: ace king", priority: .medium)
        conductor.say(lead: SoundCatalog.voShowdown, synthesis: "player 2: ten ten", priority: .medium)
        await drain()
        XCTAssertEqual(audio.log.filter { $0.id == SoundCatalog.voShowdown }.count, 1)
        XCTAssertEqual(synths().count, 2)
    }

    func testOncePerHandResetsOnNextHand() async {
        let (audio, _, conductor, _) = makeRig()
        conductor.handBegan(); conductor.say(lead: SoundCatalog.voPotAwarded)
        conductor.handBegan(); conductor.say(lead: SoundCatalog.voPotAwarded)
        await drain()
        XCTAssertEqual(audio.log.filter { $0.id == SoundCatalog.voPotAwarded }.count, 2)
    }

    // MARK: - mp3 → synthesis fallback (D-030)

    func testFallbackSpeaksWhenMp3IsMissing() async {
        let (audio, _, conductor, synths) = makeRig()
        audio.missing = [SoundCatalog.voRoleButton.rawValue]
        conductor.say(lead: SoundCatalog.voRoleButton, fallback: "sei sul bàtton", priority: .high)
        await drain()
        XCTAssertTrue(audio.log.isEmpty, "the missing mp3 must not play")
        XCTAssertEqual(synths(), ["sei sul bàtton"])
    }

    func testMp3PlaysAndFallbackStaysSilentWhenPresent() async {
        let (audio, _, conductor, synths) = makeRig()   // nothing missing
        conductor.say(lead: SoundCatalog.voRoleButton, fallback: "sei sul bàtton", priority: .high)
        await drain()
        XCTAssertEqual(audio.log.map { $0.id }, [SoundCatalog.voRoleButton])
        XCTAssertTrue(synths().isEmpty)
    }

    // MARK: - vob_ colour before the action synthesis (D-031)

    func testVobColourPlaysBeforeTheActionSynthesis() async {
        let (audio, _, conductor, synths) = makeRig()
        conductor.say(lead: SoundCatalog.vobAggressorConfident, leadCategory: .botVoice,
                      synthesis: "giocatore 2 rilancia a 60", priority: .medium)
        await drain()
        XCTAssertEqual(audio.log.map { $0.id }, [SoundCatalog.vobAggressorConfident])
        XCTAssertEqual(synths(), ["giocatore 2 rilancia a 60"])
    }

    // MARK: - The turn plays the mp3, never synthesizes the phrase (D-031)

    func testHumanTurnPlaysMp3AndOnlySynthesizesTheCallContext() async {
        let (audio, _, conductor, synths) = makeRig()
        let context = SpeechMap.text(for: .yourTurnContext(toCall: 40, pot: 120))
        conductor.flushPending()
        conductor.say(lead: SoundCatalog.voYourTurn, synthesis: context, priority: .high)
        await drain()
        XCTAssertTrue(audio.log.contains { $0.id == SoundCatalog.voYourTurn })
        XCTAssertFalse(synths().contains { $0.lowercased().contains("il tuo turno") })
        XCTAssertEqual(synths(), [context])
    }
}
