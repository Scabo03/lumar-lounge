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

    /// THE single declared list of croupier voices that represent a semantically
    /// UNIQUE moment of the hand, and so are spoken at most ONCE per hand even when
    /// the event that carries them is emitted several times (D-051, generalises the
    /// D-029/D-045 pot fix). To make a new voice once-per-hand, add it HERE — no
    /// per-event ad-hoc logic. On a repeat the croupier LEAD (its mp3, or the declared
    /// fallback) is suppressed; a per-call synthesis that legitimately differs each
    /// time (e.g. each player's hand read at showdown) still speaks.
    public static let oncePerHandVoices: Set<SoundID> = [
        SoundCatalog.voShowdown,
        SoundCatalog.voPotAwarded,
        SoundCatalog.voSplitPot,
        SoundCatalog.voOpenersDisqualified,   // openers disqualification (D-051)
        SoundCatalog.voHighStakesDraw,        // decisive-hand cue (D-053)
        SoundCatalog.voSkyShowdown,           // Skypool Omaha showdown (D-066)
        SoundCatalog.voSkyPotAwarded,         // Skypool Omaha pot (D-066)
        SoundCatalog.voSkySplitPot,           // Skypool Omaha split pot (D-066)
        SoundCatalog.voClockPokerShowdown,    // ClockTower Stud showdown (D-077)
        SoundCatalog.voClockPokerPot,         // ClockTower Stud pot (D-077)
        SoundCatalog.voClockPokerHousePrize,  // ClockTower Stud house prize (D-078)
    ]
    private static let oncePerHand: Set<String> = Set(oncePerHandVoices.map { $0.rawValue })

    public init(audio: AudioServicing, queue: AnnouncementQueue) {
        self.audio = audio
        self.queue = queue
    }

    /// Whether the conductor has nothing left to play or hand to the queue. Combined
    /// with `AnnouncementQueue.isQuiet` it tells the UI the spoken channel is idle,
    /// so the visual timeline can advance in step with the ear (D-034).
    public var isIdle: Bool { !isBusy && pending.isEmpty }

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
            } else if let fallback = item.fallback, item.leadCategory.fallsBackToSynthesis {
                // The mp3 isn't in the bundle yet → speak the declared fallback (D-030),
                // but ONLY for INFORMATIVE voices (croupier). An AMBIENT voice (bot
                // colour) falls back to SILENCE, never synthesis (D-066): a missing
                // colour line must never become an intrusive announcement.
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
