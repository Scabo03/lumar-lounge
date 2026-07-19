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
        /// A sound to play AFTER this item has spoken — for a cue whose ORDER carries
        /// information (the win/lose sting, D-085). Never before, never in parallel.
        let trailing: SoundID?
        let trailingCategory: SoundCategory
        let priority: AnnouncementPriority
        let reason: String
    }

    private let audio: AudioServicing
    private let queue: AnnouncementQueue

    private var pending: [Item] = []
    private var isBusy = false
    private var busyEstimate: TimeInterval = 0
    private var oncePerHandPlayed: Set<String> = []

    /// THE CHANNEL BUDGET (D-085). Measured on device: the conductor used to be an
    /// UNBOUNDED FIFO in front of the queue, and because it hands items over ONE AT A
    /// TIME the queue's own Strategy C never engaged — through an 18.3 s showdown burst
    /// the queue's pending depth never exceeded 1. So all the backlog, and all the
    /// desync, accumulated HERE, invisible to the queue's priority/dropping.
    ///
    /// The whole spoken channel (this pending list + what the queue still owes) is now
    /// held under this many seconds of estimated speech; beyond it, low then medium are
    /// dropped exactly as in the queue. High is never dropped, so the player never loses
    /// their own cards, their turn, or their result.
    public static let channelBudget: TimeInterval = 6.0

    /// Test seam: observes every item dropped to stay inside the channel budget.
    public var dropObserver: ((String, AnnouncementPriority) -> Void)?

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
        SoundCatalog.voTowerShowdown,         // ClockTower Stud showdown (D-077/D-080)
        SoundCatalog.voTowerPotAwarded,       // ClockTower Stud pot (D-077/D-080)
        SoundCatalog.voTowerSplitPot,         // ClockTower Stud split pot (D-080)
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

    /// Estimated seconds of speech the WHOLE spoken channel still owes: this
    /// conductor's queued items, whatever it is playing now, and the announcement
    /// queue behind it. The UI sizes its adaptive wait on this instead of a fixed cap,
    /// so legitimate long narration is waited out while a genuine hang trips fast (D-085).
    public var channelRemaining: TimeInterval {
        busyEstimate + pending.reduce(0) { $0 + estimate($1) } + queue.estimatedRemaining
    }

    /// The estimated speaking cost of an item: its mp3 (real bundled duration when we
    /// can read it) plus its synthesis line.
    private func estimate(_ item: Item) -> TimeInterval {
        var total: TimeInterval = 0
        if let lead = item.lead {
            if audio.isAvailable(lead) { total += audio.duration(of: lead) ?? 1.5 }
            else if let fallback = item.fallback, item.leadCategory.fallsBackToSynthesis {
                total += AnnouncementQueue.speakTime(fallback)
            }
        }
        if let synthesis = item.synthesis { total += AnnouncementQueue.speakTime(synthesis) }
        return total
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
                    trailing: SoundID? = nil, trailingCategory: SoundCategory = .effect,
                    priority: AnnouncementPriority = .medium, reason: String = "") {
        var lead = lead
        if let c = lead, leadCategory == .croupier, Self.oncePerHand.contains(c.rawValue) {
            if oncePerHandPlayed.contains(c.rawValue) { lead = nil } else { oncePerHandPlayed.insert(c.rawValue) }
        }
        guard lead != nil || synthesis != nil || fallback != nil || trailing != nil else { return }
        pending.append(Item(lead: lead, leadCategory: leadCategory, synthesis: synthesis,
                            fallback: fallback, trailing: trailing, trailingCategory: trailingCategory,
                            priority: priority, reason: reason))
        enforceChannelBudget()
        pump()
    }

    /// Holds the whole spoken channel under `channelBudget` seconds of estimated speech,
    /// dropping the lowest-priority WAITING item first (never a high one, never the head
    /// that is about to play). This is the same Strategy C the queue applies — it simply
    /// had to be applied HERE too, because this is where the backlog actually formed.
    private func enforceChannelBudget() {
        while channelRemaining > Self.channelBudget, let index = lowestDroppableIndex() {
            let dropped = pending.remove(at: index)
            SpokenLog.log("CHANNEL DROP [\(dropped.priority)] \(dropped.reason) \(dropped.synthesis ?? "")")
            dropObserver?(dropped.synthesis ?? dropped.fallback ?? dropped.reason, dropped.priority)
            // A trailing cue is INFORMATION-ORDERED, never dropped silently: if its
            // line goes, the cue still fires so the player is not left without it.
            if let trailing = dropped.trailing { audio.play(trailing, category: dropped.trailingCategory) }
        }
    }

    /// The waiting item to drop first: lowest priority, oldest first; never a high one.
    ///
    /// NOTE the difference from the queue's identical-looking rule (D-085): there,
    /// index 0 is the item about to be SPOKEN and must never be dropped, so it skips
    /// the head. Here `pump()` has ALREADY removed the in-flight item from `pending`,
    /// so every element in this array is genuinely waiting and every one is droppable.
    /// Copying the queue's `dropFirst()` across left almost nothing droppable (the list
    /// rarely holds more than one item) and the budget silently never bit — measured:
    /// the burst still took 18.26 s.
    private func lowestDroppableIndex() -> Int? {
        let droppable = pending.enumerated().filter { $0.element.priority != .high }
        guard let lowest = droppable.map({ $0.element.priority }).min() else { return nil }
        return droppable.first { $0.element.priority == lowest }?.offset
    }

    /// Test hook: whether a once-per-hand voice would still be admitted now.
    public func admits(_ id: SoundID) -> Bool {
        !(Self.oncePerHand.contains(id.rawValue) && oncePerHandPlayed.contains(id.rawValue))
    }

    private func pump() {
        guard !isBusy, !pending.isEmpty else { return }
        isBusy = true
        let item = pending.removeFirst()
        busyEstimate = estimate(item)
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
        // ORDER CARRIES INFORMATION (D-085): a trailing cue — the win/lose sting —
        // must land AFTER the line that says what happened, never before it. So it is
        // sequenced on the SPOKEN channel via the queue's completion, not fired off in
        // parallel by an independent consumer with its own clock.
        if let synthesis = item.synthesis {
            let trailing = item.trailing
            let category = item.trailingCategory
            queue.enqueue(synthesis, priority: item.priority) { [weak self] in
                if let trailing { self?.audio.play(trailing, category: category) }
            }
        } else if let trailing = item.trailing {
            audio.play(trailing, category: item.trailingCategory)
        }
        isBusy = false
        busyEstimate = 0
        pump()
    }
}
