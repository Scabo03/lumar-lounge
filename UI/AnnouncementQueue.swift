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

    private struct Item { let text: String; let priority: AnnouncementPriority }

    private var pending: [Item] = []
    private var current: Item?
    private var currentToken = 0
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
    /// Test seam: the currently queued (not-yet-started) items.
    public func pendingSnapshot() -> [(String, AnnouncementPriority)] { pending.map { ($0.text, $0.priority) } }

    public init() {
        #if canImport(UIKit)
        observer = NotificationCenter.default.addObserver(
            forName: UIAccessibility.announcementDidFinishNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.announcementFinished() }
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
    public func enqueue(_ text: String, priority: AnnouncementPriority) {
        guard !text.isEmpty else { return }
        insert(Item(text: text, priority: priority))
        enforceBacklog()
        SpokenLog.log("enqueue [\(priority)] \(text)  (pending=\(pending.count))")
        process()
    }

    /// A live-adjusting value (the Raise box): the ONE deliberate interruption — a
    /// new value replaces the previous so a burst of +/- collapses to the latest.
    public func announceLiveValue(_ text: String) {
        guard !text.isEmpty else { return }
        SpokenLog.log("live \(text)")
        synthesisObserver?(text)
        post(text, interrupting: true)
    }

    /// Drops queued-but-not-started announcements so a following time-critical cue
    /// (the human turn) plays promptly.
    public func flushPending() { pending.removeAll() }

    // MARK: - Croupier coordination (one spoken channel)

    /// The croupier is about to play an mp3: hold new announcements and wait for any
    /// in-progress one to finish first.
    public func beginExternalSpeech() async {
        externalSpeechActive = true
        if current != nil { await withCheckedContinuation { idleWaiters.append($0) } }
    }
    /// The croupier mp3 finished: resume the queue.
    public func endExternalSpeech() {
        externalSpeechActive = false
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
            dropObserver?(dropped.text, dropped.priority)
        }
    }

    // MARK: - Serial processing

    private func process() {
        guard current == nil, !externalSpeechActive, !pending.isEmpty else { return }
        let item = pending.removeFirst()
        current = item
        currentToken += 1
        let token = currentToken
        synthesisObserver?(item.text)
        SpokenLog.log("SPEAK [\(item.priority)] \(item.text)")
        guard isVoiceOverRunning else {
            // Nobody is listening. Either simulate the duration (app mode ON, so the
            // visuals still pace to it, D-034) or advance at once (mode OFF).
            if pacedWhenSilent { scheduleAdvance(after: Self.speakTime(item.text), token: token) }
            else { finishCurrent() }
            return
        }
        post(item.text, interrupting: false)
        // Fallback: advance if the finish notification never arrives. The cap is the
        // estimated speech time plus the 1 s max pause, so it never truncates.
        scheduleAdvance(after: Self.speakTime(item.text) + maxPause, token: token)
    }

    /// Advances to the next item after `seconds`, unless the current one already
    /// finished (token mismatch). Used for the finish-notification cap and for the
    /// silent-but-paced simulation (D-034).
    private func scheduleAdvance(after seconds: TimeInterval, token: Int) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.currentToken == token, self.current != nil else { return }
            self.finishCurrent()
        }
    }

    private func announcementFinished() {
        guard current != nil else { return }
        finishCurrent()
    }

    private func finishCurrent() {
        current = nil
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
