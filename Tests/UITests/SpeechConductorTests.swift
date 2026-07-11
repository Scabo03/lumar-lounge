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

    // MARK: - Consolidated once-per-hand de-dup (D-051)

    func testOpenersDisqualificationSpeaksOncePerHandEvenIfEmittedTwice() async {
        // The mp3 isn't produced yet → the fallback speaks; two disqualification
        // signals for the same hand must still speak it ONCE (D-051).
        let (audio, _, conductor, synths) = makeRig()
        audio.missing = [SoundCatalog.voOpenersDisqualified.rawValue]
        conductor.handBegan()
        conductor.say(lead: SoundCatalog.voOpenersDisqualified, fallback: "giocatore 3 squalificato", priority: .high)
        conductor.say(lead: SoundCatalog.voOpenersDisqualified, fallback: "giocatore 3 squalificato", priority: .high)
        await drain()
        XCTAssertTrue(audio.log.isEmpty)
        XCTAssertEqual(synths().filter { $0.contains("squalificato") }.count, 1,
                       "the disqualification line must be spoken exactly once")
    }

    func testDecisiveHandCuePlaysOncePerHand() async {
        let (audio, _, conductor, _) = makeRig()   // mp3 present in the rig
        conductor.handBegan()
        conductor.say(lead: SoundCatalog.voHighStakesDraw)
        conductor.say(lead: SoundCatalog.voHighStakesDraw)
        await drain()
        XCTAssertEqual(audio.log.filter { $0.id == SoundCatalog.voHighStakesDraw }.count, 1)
    }

    func testOncePerHandListIsTheSingleDeclaredSource() async {
        // Every once-per-hand voice is declared in ONE place and consulted by the
        // conductor (D-051) — no per-event ad-hoc logic.
        let list = SpeechConductor.oncePerHandVoices
        XCTAssertTrue(list.isSuperset(of: [
            SoundCatalog.voShowdown, SoundCatalog.voPotAwarded, SoundCatalog.voSplitPot,
            SoundCatalog.voOpenersDisqualified, SoundCatalog.voHighStakesDraw,
        ]))
        // `admits` reflects that same list: admitted before, refused after playing.
        let (_, _, conductor, _) = makeRig()
        conductor.handBegan()
        XCTAssertTrue(conductor.admits(SoundCatalog.voOpenersDisqualified))
        conductor.say(lead: SoundCatalog.voOpenersDisqualified, fallback: "x", priority: .high)
        await drain()
        XCTAssertFalse(conductor.admits(SoundCatalog.voOpenersDisqualified))
        // A voice NOT on the list is always admitted.
        XCTAssertTrue(conductor.admits(SoundCatalog.voFlop))
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
