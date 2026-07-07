// SpeechConductor.swift
// =====================================================================
// The poker-aware narration director (D-029..D-032). It sequences each event's
// pre-recorded CROUPIER voice (an mp3) and feeds its VoiceOver SYNTHESIS to the
// shared `AnnouncementQueue`. It owns:
//  • once-per-hand de-dup of the showdown/pot/split croupier voices;
//  • the mp3 → synthesis FALLBACK when a file isn't bundled yet (D-030);
//  • flush of stale narration for the time-critical turn.
//
// The croupier and the synthesis are ONE spoken channel (D-032): while a croupier
// mp3 plays, the conductor HOLDS the announcement queue (`beginExternalSpeech`)
// and waits for any in-progress announcement first; then it resumes the queue.
// Synthesis is handed to the queue fire-and-forget, so a burst (opponent actions)
// lands there and the queue applies priority + dropping — the conductor never
// blocks on speech.

import Foundation
import Audio

@MainActor
public final class SpeechConductor {

    private struct Item {
        let lead: SoundID?
        let leadCategory: SoundCategory
        let synthesis: String?
        let fallback: String?
        let priority: AnnouncementPriority
        let reason: String
    }

    private let audio: AudioServicing
    private let queue: AnnouncementQueue

    private var pending: [Item] = []
    private var isBusy = false
    private var oncePerHandPlayed: Set<String> = []

    private static let oncePerHand: Set<String> = [
        SoundCatalog.voShowdown.rawValue,
        SoundCatalog.voPotAwarded.rawValue,
        SoundCatalog.voSplitPot.rawValue,
    ]

    public init(audio: AudioServicing, queue: AnnouncementQueue) {
        self.audio = audio
        self.queue = queue
    }

    /// Resets the per-hand de-dup at the start of each hand.
    public func handBegan() { oncePerHandPlayed.removeAll() }

    /// Drops queued-but-not-started narration (conductor and queue) so a following
    /// time-critical cue plays promptly.
    public func flushPending() { pending.removeAll(); queue.flushPending() }

    /// Enqueues a spoken item: a LEAD sound (croupier/vob) then a SYNTHESIS line
    /// (either optional), with an optional mp3-missing fallback and a priority.
    public func say(lead: SoundID?, leadCategory: SoundCategory = .croupier,
                    synthesis: String? = nil, fallback: String? = nil,
                    priority: AnnouncementPriority = .medium, reason: String = "") {
        var lead = lead
        if let c = lead, leadCategory == .croupier, Self.oncePerHand.contains(c.rawValue) {
            if oncePerHandPlayed.contains(c.rawValue) { lead = nil } else { oncePerHandPlayed.insert(c.rawValue) }
        }
        guard lead != nil || synthesis != nil || fallback != nil else { return }
        pending.append(Item(lead: lead, leadCategory: leadCategory, synthesis: synthesis,
                            fallback: fallback, priority: priority, reason: reason))
        pump()
    }

    /// Test hook: whether a once-per-hand voice would still be admitted now.
    public func admits(_ id: SoundID) -> Bool {
        !(Self.oncePerHand.contains(id.rawValue) && oncePerHandPlayed.contains(id.rawValue))
    }

    private func pump() {
        guard !isBusy, !pending.isEmpty else { return }
        isBusy = true
        let item = pending.removeFirst()
        Task { await self.process(item) }
    }

    private func process(_ item: Item) async {
        if let lead = item.lead {
            if audio.isAvailable(lead) {
                // Croupier/vob mp3: hold the announcement queue and let any
                // in-progress announcement finish, then play, then resume (D-032).
                await queue.beginExternalSpeech()
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    audio.play(lead, category: item.leadCategory) { cont.resume() }
                }
                queue.endExternalSpeech()
            } else if let fallback = item.fallback {
                // The mp3 isn't in the bundle yet → speak the declared fallback (D-030).
                queue.enqueue(fallback, priority: item.priority)
            }
        }
        if let synthesis = item.synthesis {
            queue.enqueue(synthesis, priority: item.priority)
        }
        isBusy = false
        pump()
    }
}
