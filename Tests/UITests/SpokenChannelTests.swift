// SpokenChannelTests.swift
// =====================================================================
// D-085 — the spoken channel: ordering, boundedness, and the adaptive wait.
//
// These pin the three device-measured defects: an outcome cue arriving before the
// line that says what happened, an unbounded backlog behind the conductor, and a
// fixed pacing cap that could not tell honest narration from a hang.

import XCTest
@testable import UI
import Audio

@MainActor
final class SpokenChannelTests: XCTestCase {

    private func makeChannel(missing: [String] = []) -> (RecordingAudioService, AnnouncementQueue, SpeechConductor) {
        let audio = RecordingAudioService()
        audio.missing = Set(missing)
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = false      // no VoiceOver: items complete at once
        let conductor = SpeechConductor(audio: audio, queue: queue)
        conductor.handBegan()
        return (audio, queue, conductor)
    }

    /// Waits for the channel to drain, with a bound so a stuck test fails rather than hangs.
    private func drain(_ conductor: SpeechConductor, _ queue: AnnouncementQueue) async {
        for _ in 0..<400 {
            if conductor.isIdle && queue.isQuiet { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("spoken channel never drained")
    }

    // MARK: - Order carries information

    /// THE regression the player reported: the win/lose sting used to be fired by a
    /// parallel consumer on its own clock and regularly arrived BEFORE the line saying
    /// who won — spoiling the result. A trailing cue must never precede its line.
    func testOutcomeStingNeverPrecedesTheLineThatRevealsTheResult() async {
        let (audio, queue, conductor) = makeChannel()
        var spokenAt: Int?
        var order: [String] = []
        queue.synthesisObserver = { text in
            order.append("SAY:\(text)")
            spokenAt = order.count
        }
        audio.onPlay = { id, _ in order.append("PLAY:\(id.rawValue)") }

        conductor.say(lead: SoundCatalog.voPotAwarded,
                      synthesis: "hai vinto con doppia coppia",
                      trailing: SoundCatalog.fxWinHand,
                      priority: .high, reason: "pot")
        await drain(conductor, queue)

        let stingIndex = order.firstIndex { $0 == "PLAY:\(SoundCatalog.fxWinHand.rawValue)" }
        XCTAssertNotNil(stingIndex, "the outcome sting must still play: \(order)")
        XCTAssertNotNil(spokenAt, "the result line must be spoken: \(order)")
        XCTAssertGreaterThan(stingIndex! + 1, spokenAt!,
                             "the sting arrived before the result was announced: \(order)")
    }

    /// Even when its line is dropped to stay inside the budget, the cue still fires —
    /// the player is never left without it.
    func testTrailingCueStillFiresIfItsLineIsDropped() async {
        let (audio, queue, conductor) = makeChannel()
        var played: [String] = []
        audio.onPlay = { id, _ in played.append(id.rawValue) }
        // Flood the channel so the budget must drop something, then a droppable
        // line carrying a trailing cue.
        for i in 0..<12 {
            conductor.say(lead: nil, synthesis: String(repeating: "parola ", count: 12) + "\(i)",
                          priority: .medium, reason: "flood")
        }
        conductor.say(lead: nil, synthesis: String(repeating: "esito ", count: 12),
                      trailing: SoundCatalog.fxLoseHand, priority: .medium, reason: "outcome")
        await drain(conductor, queue)
        XCTAssertTrue(played.contains(SoundCatalog.fxLoseHand.rawValue),
                      "a dropped line must not swallow its trailing cue")
    }

    // MARK: - The channel is bounded

    /// The conductor used to be an UNBOUNDED FIFO in front of the queue, and because it
    /// hands items over one at a time the queue's own dropping never engaged (measured
    /// on device: through an 18.3 s burst the queue's depth never exceeded 1). The
    /// budget must now bound the WHOLE channel.
    func testChannelDoesNotAccumulateBacklogBeyondTheBudget() {
        let (_, _, conductor) = makeChannel()
        for i in 0..<25 {
            conductor.say(lead: nil, synthesis: "giocatore \(i % 3 + 1) rilancia a \(i * 100)",
                          priority: .medium, reason: "chatter")
        }
        XCTAssertLessThanOrEqual(conductor.channelRemaining, SpeechConductor.channelBudget * 1.6,
                                 "channel owes \(conductor.channelRemaining)s after a 25-line burst")
    }

    /// Boundedness must never be paid for with the RESULT of a hand: high-priority
    /// items are exempt, so a showdown is preserved whole however fast it arrives.
    func testTheResultOfAHandIsNeverDroppedToStayInBudget() {
        let (_, _, conductor) = makeChannel()
        var dropped: [AnnouncementPriority] = []
        conductor.dropObserver = { _, priority in dropped.append(priority) }
        for i in 0..<10 {
            conductor.say(lead: nil, synthesis: "giocatore \(i) chiama", priority: .medium, reason: "chatter")
        }
        for i in 0..<4 {
            conductor.say(lead: nil, synthesis: "giocatore \(i): doppia coppia, assi e dieci, kicker donna",
                          priority: .high, reason: "showdown")
        }
        XCTAssertFalse(dropped.contains(.high), "a high-priority result line was dropped")
    }

    /// Under load the OLDEST chatter goes first, so what survives is the current state
    /// of the table rather than stale history.
    func testDroppingRemovesTheStalestChatterFirst() {
        let (_, _, conductor) = makeChannel()
        var dropped: [String] = []
        conductor.dropObserver = { text, _ in dropped.append(text) }
        for i in 0..<15 {
            conductor.say(lead: nil, synthesis: "azione numero \(i) di un avversario al tavolo",
                          priority: .medium, reason: "chatter")
        }
        guard let first = dropped.first else { return XCTFail("nothing was dropped") }
        XCTAssertTrue(first.contains("numero 0") || first.contains("numero 1"),
                      "dropping should start from the stalest line, got: \(first)")
    }

    // MARK: - The adaptive wait

    /// A FIXED cap cannot serve both jobs (D-085): 8 s fired in the middle of an honest
    /// 21.7 s showdown, but raising it would freeze a real hang for as long. Sizing the
    /// wait on what the channel says it still owes separates the two.
    func testAdaptiveWaitCoversHonestNarrationButNotAHang() {
        let hang = SpokenChannelPacing.adaptiveMaxWait(channelRemaining: 0)
        XCTAssertLessThanOrEqual(hang, SpokenChannelPacing.minimumWait + 1.1,
                                 "a channel owing nothing yet not quiet is a hang: it must trip fast")

        // The measured cost of a fully preserved three-way showdown.
        let showdown = SpokenChannelPacing.adaptiveMaxWait(channelRemaining: 21.7)
        XCTAssertGreaterThanOrEqual(showdown, 21.7,
                                    "honest narration must be waited out, not cut off")
        XCTAssertLessThanOrEqual(showdown, SpokenChannelPacing.hardCeiling,
                                 "the wait must always stay under the hard ceiling")
    }

    /// However much the channel claims to owe, the UI is never blocked indefinitely —
    /// the player's ability to act outranks perfect narration.
    func testAdaptiveWaitIsAlwaysBounded() {
        for remaining in [0.0, 5.0, 50.0, 5000.0] {
            let wait = SpokenChannelPacing.adaptiveMaxWait(channelRemaining: remaining)
            XCTAssertLessThanOrEqual(wait, SpokenChannelPacing.hardCeiling)
            XCTAssertGreaterThanOrEqual(wait, SpokenChannelPacing.minimumWait)
        }
    }

    /// The wait terminates even against a channel that never goes quiet — the
    /// anti-freeze guarantee that keeps the UI from stealing the player's turn.
    func testWaitAlwaysTerminatesAgainstAChannelThatNeverGoesQuiet() async {
        let start = Date()
        let quiet = await SpokenChannelPacing.awaitQuiet(isQuiet: { false }, maxWait: 0.3, step: 0.02)
        XCTAssertFalse(quiet)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3.0, "the safeguard did not release the UI")
    }
}
