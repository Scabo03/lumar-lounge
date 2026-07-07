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
}
