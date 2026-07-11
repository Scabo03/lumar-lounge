import XCTest
@testable import UI
import Audio

/// The adaptive visual rhythm (D-034). The TableViewModel, when the app's VoiceOver
/// mode is ON, advances the visuals only when the spoken channel is quiet
/// (`conductor.isIdle && queue.isQuiet`); when OFF it uses its own fast rhythm.
/// These tests exercise that exact idle rule against a real conductor + queue.
@MainActor
final class VisualPacingTests: XCTestCase {

    /// Mimics `TableViewModel.awaitSpokenChannelQuiet`, returning the seconds waited.
    private func waitForQuiet(_ conductor: SpeechConductor, _ queue: AnnouncementQueue,
                              start: TimeInterval) async -> TimeInterval {
        while !(conductor.isIdle && queue.isQuiet) {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return Date().timeIntervalSince1970 - start
    }

    func testModeOnPacesToTheAnnouncementCompletion() async {
        let audio = RecordingAudioService()
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = false
        queue.pacedWhenSilent = true                 // app mode ON, iOS VoiceOver off
        let conductor = SpeechConductor(audio: audio, queue: queue)
        conductor.say(lead: nil, synthesis: "otto nove dieci fante donna re", priority: .high)
        let waited = await waitForQuiet(conductor, queue, start: Date().timeIntervalSince1970)
        XCTAssertGreaterThan(waited, 0.8, "the visual waits for the announcement to complete")
    }

    func testModeOffDoesNotWaitForAnnouncements() async {
        let audio = RecordingAudioService()
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = false
        queue.pacedWhenSilent = false                // app mode OFF → not paced
        let conductor = SpeechConductor(audio: audio, queue: queue)
        conductor.say(lead: nil, synthesis: "otto nove dieci fante donna re", priority: .high)
        // Give the conductor's Task a moment to run and drain the queue.
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertTrue(conductor.isIdle && queue.isQuiet, "nothing to wait for when not paced")
    }

    func testEventsWithNoAnnouncementAdvanceImmediatelyEvenInModeOn() async {
        let audio = RecordingAudioService()
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = false
        queue.pacedWhenSilent = true
        let conductor = SpeechConductor(audio: audio, queue: queue)
        conductor.say(lead: nil, synthesis: nil, priority: .medium)   // nothing to say
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertTrue(conductor.isIdle && queue.isQuiet, "a silent event doesn't stall the visuals")
    }

    // MARK: - The safeguard: the visual wait is never unbounded (D-056)

    func testSafeguardProceedsWhenTheChannelNeverGoesQuiet() async {
        let start = Date()
        // A channel that never reports quiet (the device stall: a lost mp3 completion,
        // a queue item awaiting a notification that never arrives).
        let quiet = await SpokenChannelPacing.awaitQuiet(isQuiet: { false }, maxWait: 0.3, step: 0.02)
        let waited = Date().timeIntervalSince(start)
        XCTAssertFalse(quiet, "the safeguard reports it proceeded WITHOUT the channel going quiet")
        XCTAssertGreaterThanOrEqual(waited, 0.25, "it does wait up to the safeguard before proceeding")
        XCTAssertLessThan(waited, 1.5, "but the UI never blocks indefinitely on a stuck spoken channel")
    }

    func testAwaitQuietReturnsImmediatelyWhenAlreadyQuiet() async {
        let quiet = await SpokenChannelPacing.awaitQuiet(isQuiet: { true }, maxWait: 3.0)
        XCTAssertTrue(quiet)
    }

    func testAwaitQuietStopsAsSoonAsTheChannelBecomesQuiet() async {
        var ticks = 0
        let quiet = await SpokenChannelPacing.awaitQuiet(isQuiet: { ticks += 1; return ticks > 3 },
                                                         maxWait: 3.0, step: 0.02)
        XCTAssertTrue(quiet, "it stops waiting the moment the channel is quiet, not at the safeguard")
        XCTAssertLessThan(ticks, 20, "it did not spin all the way to the safeguard")
    }

    func testAwaitQuietHonoursCancellation() async {
        let quiet = await SpokenChannelPacing.awaitQuiet(isQuiet: { false }, isCancelled: { true }, maxWait: 5.0)
        XCTAssertFalse(quiet, "a cancelled task stops waiting at once")
    }
}
