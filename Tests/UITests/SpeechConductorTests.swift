import XCTest
@testable import UI
import Audio

/// The serial speech owner (D-029/D-030/D-031): once-per-hand de-dup (the pot
/// "broken record"), the mp3→synthesis fallback, the flush for time-critical
/// cues, and lead→synthesis ordering.
@MainActor
final class SpeechConductorTests: XCTestCase {

    private func drain() async {
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    // MARK: - Pot "broken record"

    func testPotMp3PlaysOncePerHandAcrossSidePots() async {
        let audio = RecordingAudioService()
        let conductor = SpeechConductor(audio: audio)
        conductor.handBegan()
        conductor.say(lead: SoundCatalog.voPotAwarded)
        conductor.say(lead: SoundCatalog.voPotAwarded)
        conductor.say(lead: SoundCatalog.voPotAwarded)
        await drain()
        XCTAssertEqual(audio.log.filter { $0.id == SoundCatalog.voPotAwarded }.count, 1)
    }

    /// The REAL regression: a hand with three pots (main + two side) must speak the
    /// pot conclusion — mp3 AND synthesis — exactly once, not three times. Mimics
    /// `present.speakPot`'s once-per-hand guard together with the conductor.
    func testPotConclusionMp3AndSynthesisAreEachSpokenOncePerHand() async {
        let audio = RecordingAudioService()
        let conductor = SpeechConductor(audio: audio)
        var synths: [String] = []
        conductor.synthesisObserver = { synths.append($0) }
        conductor.handBegan()

        var potAnnounced = false
        func speakPot() {
            guard !potAnnounced else { return }
            potAnnounced = true
            conductor.say(lead: SoundCatalog.voPotAwarded, synthesis: "hai vinto con doppia coppia", reason: "pot")
        }
        speakPot(); speakPot(); speakPot()   // three potAwarded events in one hand
        await drain()

        XCTAssertEqual(audio.log.filter { $0.id == SoundCatalog.voPotAwarded }.count, 1, "pot mp3 once")
        XCTAssertEqual(synths.filter { $0 == "hai vinto con doppia coppia" }.count, 1, "pot conclusion once")
    }

    func testShowdownVoicePlaysOncePerHandButEachRevealIsSynthesized() async {
        let audio = RecordingAudioService()
        let conductor = SpeechConductor(audio: audio)
        var synths: [String] = []
        conductor.synthesisObserver = { synths.append($0) }
        conductor.handBegan()
        conductor.say(lead: SoundCatalog.voShowdown, synthesis: "player 1: ace king")
        conductor.say(lead: SoundCatalog.voShowdown, synthesis: "player 2: ten ten")
        await drain()
        XCTAssertEqual(audio.log.filter { $0.id == SoundCatalog.voShowdown }.count, 1, "showdown mp3 once")
        XCTAssertEqual(synths.count, 2, "each revealed hand is still read")
    }

    func testOncePerHandResetsOnNextHand() async {
        let audio = RecordingAudioService()
        let conductor = SpeechConductor(audio: audio)
        conductor.handBegan(); conductor.say(lead: SoundCatalog.voPotAwarded)
        conductor.handBegan(); conductor.say(lead: SoundCatalog.voPotAwarded)
        await drain()
        XCTAssertEqual(audio.log.filter { $0.id == SoundCatalog.voPotAwarded }.count, 2)
    }

    // MARK: - mp3 → synthesis fallback (D-030)

    func testFallbackSpeaksWhenMp3IsMissing() async {
        let audio = RecordingAudioService()
        audio.missing = [SoundCatalog.voRoleButton.rawValue]   // file not in the bundle yet
        let conductor = SpeechConductor(audio: audio)
        var synths: [String] = []
        conductor.synthesisObserver = { synths.append($0) }
        conductor.say(lead: SoundCatalog.voRoleButton, fallback: "sei sul bàtton")
        await drain()
        XCTAssertTrue(audio.log.isEmpty, "the missing mp3 must not play")
        XCTAssertEqual(synths, ["sei sul bàtton"], "the fallback synthesis speaks")
    }

    func testMp3PlaysAndFallbackStaysSilentWhenPresent() async {
        let audio = RecordingAudioService()   // nothing missing → voRoleButton is 'present'
        let conductor = SpeechConductor(audio: audio)
        var synths: [String] = []
        conductor.synthesisObserver = { synths.append($0) }
        conductor.say(lead: SoundCatalog.voRoleButton, fallback: "sei sul bàtton")
        await drain()
        XCTAssertEqual(audio.log.map { $0.id }, [SoundCatalog.voRoleButton], "the mp3 plays")
        XCTAssertTrue(synths.isEmpty, "the fallback stays silent once the file is present")
    }

    // MARK: - vob_ colour before the action synthesis (D-031)

    func testVobColourPlaysBeforeTheActionSynthesis() async {
        let audio = RecordingAudioService()
        let conductor = SpeechConductor(audio: audio)
        var synths: [String] = []
        conductor.synthesisObserver = { synths.append($0) }
        conductor.say(lead: SoundCatalog.vobAggressorConfident, leadCategory: .botVoice,
                      synthesis: "giocatore 2 rilancia a 60")
        await drain()
        XCTAssertEqual(audio.log.map { $0.id }, [SoundCatalog.vobAggressorConfident], "vob_ plays (as the lead)")
        XCTAssertEqual(synths, ["giocatore 2 rilancia a 60"], "then the synthesis")
    }

    // MARK: - The human turn plays the mp3, never synthesizes the turn phrase (D-031)

    func testHumanTurnPlaysMp3AndOnlySynthesizesTheCallContext() async {
        let audio = RecordingAudioService()
        let conductor = SpeechConductor(audio: audio)
        var synths: [String] = []
        conductor.synthesisObserver = { synths.append($0) }
        // Mimic runHumanTurn with something to call.
        let context = SpeechMap.text(for: .yourTurnContext(toCall: 40, pot: 120))
        conductor.flushPending()
        conductor.say(lead: SoundCatalog.voYourTurn, synthesis: context, reason: "your-turn")
        await drain()
        XCTAssertTrue(audio.log.contains { $0.id == SoundCatalog.voYourTurn }, "the turn mp3 plays")
        XCTAssertFalse(synths.contains { $0.lowercased().contains("il tuo turno") || $0.lowercased().contains("your turn") },
                       "the turn phrase is spoken by the mp3, never synthesized")
        XCTAssertEqual(synths, [context], "only the call context is synthesized")
    }

    func testHumanCheckTurnPlaysMp3WithNoSynthesis() async {
        let audio = RecordingAudioService()
        let conductor = SpeechConductor(audio: audio)
        var synths: [String] = []
        conductor.synthesisObserver = { synths.append($0) }
        conductor.say(lead: SoundCatalog.voYourTurn, synthesis: nil, reason: "your-turn") // nothing to call
        await drain()
        XCTAssertEqual(audio.log.map { $0.id }, [SoundCatalog.voYourTurn])
        XCTAssertTrue(synths.isEmpty)
    }

    // MARK: - Flush for the time-critical turn

    func testFlushDropsQueuedNarrationSoTheTurnPlaysPromptly() async {
        let audio = RecordingAudioService()
        audio.missing = [SoundCatalog.voHandStart.rawValue, SoundCatalog.voFlop.rawValue] // make leads instant/no-op
        let conductor = SpeechConductor(audio: audio)
        // Backlog of narration, then the turn cue jumps it.
        conductor.say(lead: SoundCatalog.voHandStart)
        conductor.say(lead: SoundCatalog.voFlop)
        conductor.flushPending()
        conductor.say(lead: SoundCatalog.voYourTurn, reason: "your-turn")
        await drain()
        XCTAssertTrue(audio.log.contains { $0.id == SoundCatalog.voYourTurn }, "the turn cue plays")
    }
}
