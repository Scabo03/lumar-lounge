// AnnouncementQueue.swift
// =====================================================================
// The project-wide, game-agnostic serial channel for VoiceOver announcements
// (D-032). Every spoken announcement in the app goes through here — there is no
// direct `UIAccessibility.post` in application code any more. Reusable by any
// future game (blackjack, roulette) and any spoken part of the project.
//
// Strategy C (chosen from real data — see D-032): a FIFO queue with PRIORITY and
// DROPPING. Measurement of a representative poker session showed the serial
// speaker over-saturated at ~147% (154 s of speech in a 105 s session), almost all
// of it medium (opponent actions) and low (card content); a strict FIFO would fall
// ~50 s behind. But the HIGH-priority personal announcements are only ~2% of the
// load. So: high-priority items are never dropped and bump ahead; low then medium
// are dropped when the backlog would otherwise delay them.
//
// Rules:
//  • No announcement is ever truncated by another: a started one always finishes.
//  • Completion is detected via `announcementDidFinishNotification`; a per-item
//    cap (estimated duration + 1 s max pause) is the fallback if it never arrives.
//  • Coexists with the croupier voices (`SpeechConductor`) as ONE spoken channel:
//    while a croupier mp3 plays the queue holds; the croupier waits for the
//    in-progress announcement before playing.

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import Audio

/// Announcement importance (D-032). Personal/critical = high (never dropped);
/// opponent info = medium; secondary description (card content) = low.
public enum AnnouncementPriority: Int, Comparable, Sendable {
    case low = 0, medium = 1, high = 2
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

@MainActor
public final class AnnouncementQueue {

    private struct Item {
        let text: String
        let priority: AnnouncementPriority
        /// Fires when this item has been SPOKEN — or when it is dropped, so a caller
        /// sequencing something after it (an outcome effect, D-085) is never stranded.
        let completion: (() -> Void)?
        /// Retries left when VoiceOver drops the post because it is busy (D-108).
        var retriesLeft: Int = maxRetries
    }

    /// How many times a dropped announcement is re-posted before giving up (D-108).
    /// VoiceOver drops a post when it is busy — speaking the button the player just
    /// activated, or not yet settled after the previous line in a rapid burst — and
    /// reports it "finished" instantly. A handful of retries with a short settle
    /// recovers the line once VoiceOver is free; the cap stops a runaway loop.
    static let maxRetries = 4
    /// Delay before re-posting a dropped announcement, to let VoiceOver settle (D-108).
    /// Internal so tests can shrink it and exercise the retry deterministically.
    var retryDelay: TimeInterval = 0.4

    private var pending: [Item] = []
    private var current: Item?
    private var currentToken = 0
    /// The token whose finish (notification or timeout) we are still awaiting, so a
    /// stale/duplicate finish for an already-resolved post can never fail the current
    /// one (D-108). -1 = nothing awaited.
    private var awaitingFinishToken = -1
    /// Monotonic start of the item being spoken, so the trace can report its REAL
    /// duration on finish (D-107), not just its estimate.
    private var currentSpeakStart: UInt64 = 0
    private var externalSpeechActive = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var observer: NSObjectProtocol?

    /// Max estimated backlog (seconds of speech) kept for non-high items; beyond
    /// this, low then medium are dropped so high stays timely (Strategy C).
    private let maxBacklog: TimeInterval = 2.0
    /// Max pause after an announcement's expected end before advancing anyway.
    private let maxPause: TimeInterval = 1.0

    /// Test seam: observes every announcement actually spoken (VoiceOver posting is
    /// a no-op off-device). Also fires for live values.
    public var synthesisObserver: ((String) -> Void)?
    /// Test seam: observes every dropped announcement (Strategy C).
    public var dropObserver: ((String, AnnouncementPriority) -> Void)?
    /// Test seam: override the VoiceOver-running state (nil = ask the system).
    public var voiceOverOverride: Bool?
    /// When true, announcements take their ESTIMATED speaking time even if nobody
    /// is listening (iOS VoiceOver off) — so the app's own VoiceOver mode can pace
    /// the visuals to the theoretical announcement durations (D-034).
    public var pacedWhenSilent = false

    /// Whether the spoken channel is idle: nothing speaking, nothing queued, and no
    /// croupier mp3 holding it. Lets the UI advance the visual timeline in step with
    /// the ear when the app's VoiceOver mode is on (D-034).
    public var isQuiet: Bool { current == nil && pending.isEmpty && !externalSpeechActive }
    /// Estimated seconds of speech still owed by this queue: what is being spoken now
    /// plus everything queued behind it. The UI uses it to size its wait ADAPTIVELY
    /// instead of against a fixed cap (D-085).
    public var estimatedRemaining: TimeInterval {
        (current.map { Self.speakTime($0.text) } ?? 0) + pending.reduce(0) { $0 + Self.speakTime($1.text) }
    }

    /// Test seam: the currently queued (not-yet-started) items.
    public func pendingSnapshot() -> [(String, AnnouncementPriority)] { pending.map { ($0.text, $0.priority) } }

    /// The lowest priority among this queue's DROPPABLE (non-high) pending items, or
    /// nil if none. Lets the conductor compare it against its own pending and drop the
    /// GLOBALLY lowest item across the whole spoken channel (D-108) — because the budget
    /// is measured across both stages but was being ENFORCED per-stage, so a valuable
    /// item arriving at the conductor was dropped while lower-priority chatter sat here.
    public func lowestPendingPriority() -> AnnouncementPriority? {
        pending.filter { $0.priority != .high }.map { $0.priority }.min()
    }

    /// Drops this queue's single lowest-priority (oldest among ties) non-high pending
    /// item, firing its completion so nothing sequenced behind it is stranded (D-108).
    /// Returns true if one was dropped. Called by the conductor's channel-budget pass.
    @discardableResult
    public func dropLowestPending() -> Bool {
        guard let minPrio = pending.filter({ $0.priority != .high }).map({ $0.priority }).min(),
              let idx = pending.firstIndex(where: { $0.priority == minPrio }) else { return false }
        let dropped = pending.remove(at: idx)
        SpokenLog.log("CHANNEL DROP (queue) [\(dropped.priority)] \(dropped.text)")
        Diagnostics.shared.record("q.drop",
            ["text": dropped.text, "prio": "\(dropped.priority)", "reason": "channelBudget"])
        dropObserver?(dropped.text, dropped.priority)
        dropped.completion?()
        return true
    }

    public init() {
        #if canImport(UIKit)
        observer = NotificationCenter.default.addObserver(
            forName: UIAccessibility.announcementDidFinishNotification, object: nil, queue: .main
        ) { [weak self] note in
            // D-108: iOS reports whether the announcement was ACTUALLY spoken. When
            // VoiceOver is busy it fires this immediately with wasSuccessful=false —
            // the line was dropped, not spoken. Carry the flag so the queue can retry.
            let ok = note.userInfo?[UIAccessibility.announcementWasSuccessfulUserInfoKey] as? Bool
            Task { @MainActor [weak self] in self?.announcementFinished(wasSuccessful: ok) }
        }
        #endif
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    public var isVoiceOverRunning: Bool {
        if let voiceOverOverride { return voiceOverOverride }
        #if canImport(UIKit)
        return UIAccessibility.isVoiceOverRunning
        #else
        return false
        #endif
    }

    // MARK: - Public API

    /// Enqueues an announcement. Serial, never truncating; low/medium may be
    /// dropped under backlog to keep high-priority timely (Strategy C).
    public func enqueue(_ text: String, priority: AnnouncementPriority,
                        completion: (() -> Void)? = nil) {
        guard !text.isEmpty else { completion?(); return }
        insert(Item(text: text, priority: priority, completion: completion))
        enforceBacklog()
        SpokenLog.log("enqueue [\(priority)] \(text)  (pending=\(pending.count))")
        Diagnostics.shared.record("q.enqueue",
            ["text": text, "prio": "\(priority)", "pending": pending.count,
             "speaking": current != nil, "voRunning": isVoiceOverRunning])
        process()
    }

    /// A live-adjusting value (the Raise box): the ONE deliberate interruption — a
    /// new value replaces the previous so a burst of +/- collapses to the latest.
    public func announceLiveValue(_ text: String) {
        guard !text.isEmpty else { return }
        SpokenLog.log("live \(text)")
        // The live value is the ONE deliberate interruption: if something is being
        // spoken it truncates it. Record both so the trace shows the cut and its cause.
        if let victim = current {
            Diagnostics.shared.record("q.truncate",
                ["victim": victim.text, "by": text, "cause": "liveValue"])
        }
        Diagnostics.shared.record("q.live", ["text": text])
        synthesisObserver?(text)
        post(text, interrupting: true)
    }

    /// Drops queued-but-not-started announcements so a following time-critical cue
    /// (the human turn) plays promptly.
    ///
    /// D-106: HIGH-priority announcements are KEPT. Strategy C's founding invariant
    /// is that high is never dropped — the player never loses their own cards, their
    /// turn, or their result — but this flush swept the list unconditionally, so a
    /// line the player was entitled to could be destroyed by the prompt that came
    /// after it. The time-critical cue is itself high and simply queues behind them,
    /// which is the right order anyway: hear your cards, then be asked to act.
    public func flushPending() {
        for item in pending {
            Diagnostics.shared.record("q.flush",
                ["text": item.text, "prio": "\(item.priority)", "kept": item.priority == .high])
        }
        let dropped = pending.filter { $0.priority != .high }
        pending.removeAll { $0.priority != .high }
        for item in dropped { item.completion?() }
    }

    /// Asks VoiceOver to re-scan a newly appeared screen/modal and move focus (the
    /// focus-landing pattern, D-057). This is NOT an announcement, but VoiceOver
    /// posting lives ONLY here (the single-point rule, D-032), so focus landing routes
    /// through this one method rather than posting directly.
    public static func postScreenChanged() {
        // A `.screenChanged` INTERRUPTS whatever VoiceOver is currently speaking and
        // re-reads the focused element — the very mechanism behind "the box cut off
        // the line". Recorded so the trace can correlate the cut with the post (D-107).
        Diagnostics.shared.record("focus.screenChanged")
        #if canImport(UIKit)
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        #endif
    }

    /// Tells VoiceOver that part of the CURRENT screen changed (D-092). This is the
    /// quiet sibling of `postScreenChanged`: it is what a modal DISMISSAL needs, where
    /// the screen did not change — an element vanished out from under the cursor. A
    /// `.screenChanged` here would re-announce the whole table every single hand.
    /// Posting still lives only in this file (the single-point rule, D-032).
    public static func postLayoutChanged() {
        // `.layoutChanged` moves focus without a full re-scan; it too re-reads the
        // focused element and can talk over the queue (D-092/D-107).
        Diagnostics.shared.record("focus.layoutChanged")
        #if canImport(UIKit)
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
        #endif
    }

    // MARK: - Croupier coordination (one spoken channel)

    /// The croupier is about to play an mp3: hold new announcements and wait for any
    /// in-progress one to finish first.
    public func beginExternalSpeech() async {
        externalSpeechActive = true
        Diagnostics.shared.record("q.hold.begin", ["waiting": current != nil])
        if current != nil { await withCheckedContinuation { idleWaiters.append($0) } }
    }
    /// The croupier mp3 finished: resume the queue.
    public func endExternalSpeech() {
        externalSpeechActive = false
        Diagnostics.shared.record("q.hold.end")
        process()
    }

    // MARK: - Ordering & dropping

    private func insert(_ item: Item) {
        if item.priority == .high {
            let idx = (pending.lastIndex { $0.priority == .high }).map { $0 + 1 } ?? 0
            pending.insert(item, at: idx)   // bump ahead of medium/low, FIFO among highs
        } else {
            pending.append(item)
        }
    }

    /// The pending item to drop first: lowest priority (low before medium), oldest
    /// first; never a high-priority one and never the head (which plays next).
    private func lowestDroppableIndex() -> Int? {
        let droppable = pending.enumerated().dropFirst().filter { $0.element.priority != .high }
        guard let minPrio = droppable.map({ $0.element.priority }).min() else { return nil }
        return droppable.first { $0.element.priority == minPrio }?.offset
    }

    private func enforceBacklog() {
        // Backlog = the items WAITING behind the next one (the head always plays,
        // so a lone announcement — however long — is never dropped).
        func backlog() -> TimeInterval { pending.dropFirst().reduce(0) { $0 + Self.speakTime($1.text) } }
        while pending.count > 1, backlog() > maxBacklog, let idx = lowestDroppableIndex() {
            let dropped = pending.remove(at: idx)
            SpokenLog.log("DROP [\(dropped.priority)] \(dropped.text)")
            Diagnostics.shared.record("q.drop",
                ["text": dropped.text, "prio": "\(dropped.priority)",
                 "backlog": backlog(), "reason": "queueBacklog"])
            dropObserver?(dropped.text, dropped.priority)
            dropped.completion?()      // never strand a caller sequenced behind it
        }
    }

    // MARK: - Serial processing

    private func process() {
        guard current == nil, !externalSpeechActive, !pending.isEmpty else { return }
        let item = pending.removeFirst()
        current = item
        currentToken += 1
        currentSpeakStart = DispatchTime.now().uptimeNanoseconds
        let token = currentToken
        synthesisObserver?(item.text)
        SpokenLog.log("SPEAK [\(item.priority)] \(item.text)")
        Diagnostics.shared.record("q.speak.start",
            ["text": item.text, "prio": "\(item.priority)", "token": token,
             "estDur": Self.speakTime(item.text), "voRunning": isVoiceOverRunning,
             "pendingBehind": pending.count])
        guard isVoiceOverRunning else {
            // Nobody is listening. Either simulate the duration (app mode ON, so the
            // visuals still pace to it, D-034) or advance at once (mode OFF).
            if pacedWhenSilent { awaitingFinishToken = token; scheduleAdvance(after: Self.speakTime(item.text), token: token) }
            else { finishCurrent() }
            return
        }
        post(item.text, interrupting: false)
        // Fallback: advance if the finish notification never arrives. The cap is the
        // estimated speech time plus the 1 s max pause, so it never truncates.
        awaitingFinishToken = token
        scheduleAdvance(after: Self.speakTime(item.text) + maxPause, token: token)
    }

    /// Advances to the next item after `seconds`, unless the current one already
    /// finished (token mismatch). Used for the finish-notification cap and for the
    /// silent-but-paced simulation (D-034).
    private func scheduleAdvance(after seconds: TimeInterval, token: Int) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.currentToken == token, self.current != nil else { return }
            // The notification never came within the cap: treat as spoken (nil).
            self.announcementFinished(wasSuccessful: nil)
        }
    }

    /// Handles the end of the current announcement — from the OS finish notification
    /// (carrying `wasSuccessful`) or the fallback timeout (`nil`, i.e. assume spoken).
    ///
    /// D-108 — THE CORE FIX. VoiceOver drops a post when it is BUSY (speaking the
    /// button the player just activated, or not yet settled after the previous line in
    /// a rapid burst) and reports it "finished" INSTANTLY with `wasSuccessful == false`.
    /// The queue used to advance on that and discard the line — so the player's own
    /// action result, their split confirmations and their settlement were never spoken
    /// (measured: 42% of blackjack lines on device). Now a line that did not actually
    /// render — reported unsuccessful, or "finished" implausibly early for its length —
    /// is RE-POSTED once VoiceOver has settled, rather than lost.
    func announcementFinished(wasSuccessful: Bool?) {
        // Ignore a stale/duplicate finish for a post already resolved (by the other of
        // notification/timeout, or by a previous finish): only the awaited token counts.
        guard let item = current, awaitingFinishToken == currentToken else { return }
        awaitingFinishToken = -1

        let airtime = Double(DispatchTime.now().uptimeNanoseconds &- currentSpeakStart) / 1_000_000_000
        // A multi-word line cannot render in a few hundredths of a second: an
        // implausibly early finish means VoiceOver dropped it, even if it didn't say so.
        let failThreshold = min(0.4, 0.5 * Self.speakTime(item.text))
        let dropped = (wasSuccessful == false) || (airtime < failThreshold)

        if dropped, item.retriesLeft > 0 {
            Diagnostics.shared.record("q.retry",
                ["text": item.text, "prio": "\(item.priority)", "airtime": airtime,
                 "retriesLeft": item.retriesLeft - 1,
                 "reason": wasSuccessful == false ? "unsuccessful" : "instant"])
            SpokenLog.log("RETRY [\(item.priority)] \(item.text) (airtime=\(airtime))")
            var retry = item; retry.retriesLeft -= 1
            current = nil
            pending.insert(retry, at: 0)     // next up, ahead of everything
            // A croupier waiting via beginExternalSpeech must not hang on the retry:
            // let it proceed; the retried line is at the head for after (endExternalSpeech).
            let waiters = idleWaiters; idleWaiters.removeAll()
            for w in waiters { w.resume() }
            // Re-post after a settle so VoiceOver is free; do NOT fire completion — the
            // line has not been delivered yet.
            scheduleRetry()
            return
        }
        finishCurrent(spokenOK: !dropped)
    }

    /// Re-posts the head (a retried item) after `retryDelay`, once VoiceOver has settled.
    private func scheduleRetry() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.retryDelay ?? 0.4) * 1_000_000_000))
            guard let self else { return }
            if !self.externalSpeechActive { self.process() }
        }
    }

    private func finishCurrent(spokenOK: Bool = true) {
        let finished = current
        if let finished {
            let dur = Double(DispatchTime.now().uptimeNanoseconds &- currentSpeakStart) / 1_000_000_000
            Diagnostics.shared.record("q.speak.end",
                ["text": finished.text, "prio": "\(finished.priority)",
                 "actualDur": dur, "estDur": Self.speakTime(finished.text), "spokenOK": spokenOK])
        }
        current = nil
        finished?.completion?()
        let waiters = idleWaiters; idleWaiters.removeAll()
        for w in waiters { w.resume() }
        if !externalSpeechActive { process() }
    }

    // MARK: - Posting (the ONLY UIAccessibility.post in the app)

    private func post(_ text: String, interrupting: Bool) {
        #if canImport(UIKit)
        guard UIAccessibility.isVoiceOverRunning else { return }
        if interrupting {
            var attributed = AttributedString(text)
            attributed.accessibilitySpeechAnnouncementPriority = .high
            // Bridge to NSAttributedString or the priority is dropped (D-027).
            UIAccessibility.post(notification: .announcement, argument: NSAttributedString(attributed))
        } else {
            UIAccessibility.post(notification: .announcement, argument: text)
        }
        #endif
    }

    /// Estimated Italian VoiceOver speaking time for a phrase (drop/cap heuristic).
    static func speakTime(_ text: String) -> TimeInterval { 0.5 + Double(text.count) * 0.07 }
}
