import XCTest
@testable import UI
import Audio

/// The project-wide serial VoiceOver announcement channel (D-032, Strategy C):
/// serial without truncation, priority bump, dropping under backlog, the 1 s cap
/// fallback, and croupier coordination.
@MainActor
final class AnnouncementQueueTests: XCTestCase {

    // MARK: - Serial, no truncation

    func testAnnouncementsSpeakInArrivalOrder() async {
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = false            // no VoiceOver → drains synchronously, in order
        var spoken: [String] = []
        queue.synthesisObserver = { spoken.append($0) }
        queue.enqueue("uno", priority: .medium)
        queue.enqueue("due", priority: .medium)
        queue.enqueue("tre", priority: .medium)
        await Task.yield()
        XCTAssertEqual(spoken, ["uno", "due", "tre"])
    }

    // MARK: - Strategy C: drop low/medium under backlog, never high

    func testBurstDropsLowMediumButNeverHigh() {
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = true             // VoiceOver "on" → items wait, backlog builds
        var dropped: [(String, AnnouncementPriority)] = []
        queue.dropObserver = { dropped.append(($0, $1)) }
        // A burst of five arriving faster than they can be spoken.
        queue.enqueue("giocatore 1 rilancia a 60", priority: .medium)   // becomes current
        queue.enqueue("giocatore 2 folda", priority: .medium)
        queue.enqueue("asso di picche, dieci di cuori, tre di fiori", priority: .low)
        queue.enqueue("giocatore 3 chiama", priority: .medium)
        queue.enqueue("le tue carte: asso di picche, re di cuori", priority: .high)
        XCTAssertFalse(dropped.contains { $0.1 == .high }, "high-priority announcements are never dropped")
        XCTAssertGreaterThan(dropped.count, 0, "under backlog, some low/medium are dropped")
    }

    func testHighPriorityBumpsAheadOfPendingMediumAndLow() {
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = true             // hold so nothing drains
        queue.enqueue("medium-current", priority: .medium)   // becomes current
        queue.enqueue("low-1", priority: .low)
        queue.enqueue("HIGH", priority: .high)
        let pendingPrios = queue.pendingSnapshot().map { $0.1 }
        XCTAssertEqual(pendingPrios.first, .high, "high is bumped to the front of the pending queue")
    }

    // MARK: - 1 s cap fallback (no finish notification off-device)

    func testCapAdvancesWhenNoFinishNotificationArrives() async {
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = true             // waits for finish/cap; no VoiceOver posts finish here
        var spoken: [String] = []
        queue.synthesisObserver = { spoken.append($0) }
        queue.enqueue("uno", priority: .medium)    // current, observed
        queue.enqueue("due", priority: .medium)    // waits behind "uno"
        XCTAssertEqual(spoken, ["uno"])
        try? await Task.sleep(nanoseconds: 2_500_000_000)  // past the per-item cap
        XCTAssertEqual(spoken, ["uno", "due"], "the cap advances to the next when no finish arrives")
    }

    // MARK: - No direct UIAccessibility.post outside the queue (D-032)

    func testNoDirectUIAccessibilityPostOutsideTheQueue() throws {
        // Locate the repo's UI/ directory from this test file's path.
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let uiDir = repo.appendingPathComponent("UI")
        let files = try FileManager.default.contentsOfDirectory(at: uiDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "could not locate UI sources at \(uiDir.path)")
        for file in files where file.lastPathComponent != "AnnouncementQueue.swift" {
            let src = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(src.contains("UIAccessibility.post"),
                           "\(file.lastPathComponent) posts to VoiceOver directly — route it through AnnouncementQueue (D-032)")
        }
    }

    // MARK: - Croupier coordination (one spoken channel)

    func testQueueHoldsWhileCroupierIsSpeakingThenResumes() async {
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = true
        var spoken: [String] = []
        queue.synthesisObserver = { spoken.append($0) }
        await queue.beginExternalSpeech()          // croupier mp3 "playing"
        queue.enqueue("held", priority: .high)
        XCTAssertFalse(spoken.contains("held"), "synthesis holds while the croupier speaks")
        queue.endExternalSpeech()
        XCTAssertTrue(spoken.contains("held"), "it resumes once the croupier finishes")
    }
}
