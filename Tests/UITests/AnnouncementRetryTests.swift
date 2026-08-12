// AnnouncementRetryTests.swift
// =====================================================================
// D-108 — the core fix, from the Phase-2 device trace.
//
// On device, VoiceOver DROPS an announcement when it is busy (speaking the button
// the player just activated, or not yet settled after the previous line in a
// rapid burst) and fires `announcementDidFinishNotification` INSTANTLY with
// `wasSuccessful == false`. The queue used to advance on that and discard the line
// — measured: 42% of blackjack lines lost, including the player's own action
// result, their split confirmations, and the entire multi-hand settlement. The
// queue now RE-POSTS a line that did not actually render, rather than losing it.
//
// These tests drive the queue's finish path directly (VoiceOver is off under
// `swift test`, so the real notification never comes) with the retry delay shrunk,
// exercising the exact decision the device makes.

import XCTest
@testable import UI

@MainActor
final class AnnouncementRetryTests: XCTestCase {

    private func makeQueue() -> AnnouncementQueue {
        let q = AnnouncementQueue()
        q.voiceOverOverride = true   // take the posting path (current + awaited token)
        q.retryDelay = 0.02
        return q
    }

    /// A line iOS reports as NOT spoken is re-posted and eventually delivered — never lost.
    func testADroppedLineIsRetriedNotLost() async throws {
        let q = makeQueue()
        var spoken: [String] = []; q.synthesisObserver = { spoken.append($0) }
        var completed = 0
        q.enqueue("Il banco: 20. Mano 1: Perdi 400.", priority: .high) { completed += 1 }
        XCTAssertEqual(spoken.count, 1, "posted once")

        q.announcementFinished(wasSuccessful: false)     // VoiceOver dropped it
        XCTAssertEqual(completed, 0, "a dropped line is NOT completed — it is retried")
        XCTAssertTrue(q.pendingSnapshot().contains { $0.0.hasPrefix("Il banco") },
                      "the line is re-queued for retry, not discarded")

        try await Task.sleep(nanoseconds: 80_000_000)    // let the retry re-post
        XCTAssertEqual(spoken.count, 2, "the line was re-posted")

        // Now it genuinely renders: a real successful finish arrives after real airtime.
        try await Task.sleep(nanoseconds: 450_000_000)
        q.announcementFinished(wasSuccessful: true)
        XCTAssertEqual(completed, 1, "delivered after a successful retry")
    }

    /// An implausibly EARLY finish (near-zero airtime for a multi-word line) is treated
    /// as a drop even without the flag — the 0.00–0.09 s finishes seen on device.
    func testAnInstantFinishIsTreatedAsADrop() async throws {
        let q = makeQueue()
        var spoken: [String] = []; q.synthesisObserver = { spoken.append($0) }
        q.enqueue("In tutto: meno 1200.", priority: .high)
        q.announcementFinished(wasSuccessful: nil)       // notification with no flag, instant
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(spoken.count, 2, "an instant finish triggers a retry")
    }

    /// Retries are bounded: after the cap the line is given up (completion fires) so it
    /// can never loop forever — even with the exponential backoff between re-posts.
    func testRetriesAreBounded() async throws {
        let q = makeQueue()
        q.retryDelay = 0.005                       // tiny base; backoff stays sub-second
        var completed = 0
        var posts = 0; q.synthesisObserver = { _ in posts += 1 }
        q.enqueue("A te la parola.", priority: .high) { completed += 1 }
        // Drop it repeatedly; each drop must re-post (until the cap) or give up.
        for _ in 0...AnnouncementQueue.maxRetries {
            let before = posts
            q.announcementFinished(wasSuccessful: false)
            if completed > 0 { break }              // gave up
            // Wait for the (backoff-delayed) re-post before dropping again.
            var waited = 0
            while posts == before, waited < 100 { try await Task.sleep(nanoseconds: 10_000_000); waited += 1 }
        }
        XCTAssertEqual(completed, 1, "after the retry cap the line is given up exactly once")
        XCTAssertEqual(posts, AnnouncementQueue.maxRetries + 1,
                       "posted once, then re-posted exactly maxRetries times")
    }

    /// A normal, real finish completes once and is not retried.
    func testANormalFinishIsNotRetried() async throws {
        let q = makeQueue()
        var spoken: [String] = []; q.synthesisObserver = { spoken.append($0) }
        var completed = 0
        q.enqueue("le tue carte: asso di picche, re di cuori", priority: .high) { completed += 1 }
        try await Task.sleep(nanoseconds: 450_000_000)      // real airtime passes
        q.announcementFinished(wasSuccessful: true)
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(spoken.count, 1, "spoken once, no retry")
        XCTAssertFalse(q.pendingSnapshot().contains { $0.0.hasPrefix("le tue carte") })
    }

    /// A stale/duplicate finish after the item already resolved is a no-op (D-108 token
    /// guard) — it must not fire a spurious retry.
    func testADuplicateFinishIsIgnored() async throws {
        let q = makeQueue()
        var completed = 0
        q.enqueue("Vinci 400.", priority: .high) { completed += 1 }
        try await Task.sleep(nanoseconds: 450_000_000)
        q.announcementFinished(wasSuccessful: true)         // resolved
        XCTAssertEqual(completed, 1)
        let pendingBefore = q.pendingSnapshot().count
        q.announcementFinished(wasSuccessful: false)        // stale duplicate
        XCTAssertEqual(completed, 1, "a duplicate finish does not re-complete")
        XCTAssertEqual(q.pendingSnapshot().count, pendingBefore, "and causes no spurious retry")
    }
}
