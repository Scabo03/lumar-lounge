// SpeechConductor.swift
// =====================================================================
// The serial owner of everything SPOKEN (D-029/D-030/D-031): the pre-recorded
// voices (croupier and bot colour) and the VoiceOver synthesizer. Each item is a
// LEAD sound (optional) followed by a SYNTHESIS line (optional), played one at a
// time so nothing overlaps and the order is guaranteed (e.g. "flop" mp3 → its
// cards; a bot's vob_ colour → "player 2 raises to 60"; croupier "all-in" → its
// attribution).
//
// Three behaviours worth calling out:
//  • Once-per-hand de-dup of the showdown/pot/split croupier voices — a hand with
//    side pots emits several events; the voice still plays once (D-029).
//  • mp3 → synthesis FALLBACK (D-030): if a lead mp3 isn't in the bundle yet, a
//    declared synthesis speaks instead; when the file is later added, it plays
//    automatically and the fallback goes quiet. General, for gradual audio
//    production (new croupiers, new bot personalities).
//  • flush(): a time-critical cue (the human's turn) drops stale narrative so it
//    isn't stuck behind a backlog of mp3s.

import Foundation
import Audio

@MainActor
public final class SpeechConductor {

    private struct Item {
        let lead: SoundID?
        let leadCategory: SoundCategory
        let synthesis: String?
        let fallback: String?
        let reason: String
    }

    private let audio: AudioServicing
    private let announcer: Announcer

    private var queue: [Item] = []
    private var isSpeaking = false
    private var oncePerHandPlayed: Set<String> = []

    /// Croupier voices that must play at most once per hand.
    private static let oncePerHand: Set<String> = [
        SoundCatalog.voShowdown.rawValue,
        SoundCatalog.voPotAwarded.rawValue,
        SoundCatalog.voSplitPot.rawValue,
    ]

    #if DEBUG
    /// When true, prints each enqueue with its reason and de-dup verdict (D-030).
    public static var logging = false
    #endif

    /// Test seam: observes every synthesis line actually spoken (VoiceOver posting
    /// is a no-op off-device, so this is how tests verify the spoken layer).
    public var synthesisObserver: ((String) -> Void)?

    public init(audio: AudioServicing, announcer: Announcer = Announcer()) {
        self.audio = audio
        self.announcer = announcer
    }

    /// Resets the per-hand de-dup at the start of each hand.
    public func handBegan() { oncePerHandPlayed.removeAll() }

    /// Drops queued-but-not-yet-started narration so a following time-critical cue
    /// (the human's turn) plays promptly instead of waiting behind a backlog.
    public func flushPending() { queue.removeAll() }

    /// Enqueues a spoken item: a LEAD sound then a SYNTHESIS line (either optional).
    /// De-dupes once-per-hand croupier leads; applies the mp3→synthesis fallback.
    public func say(lead: SoundID?, leadCategory: SoundCategory = .croupier,
                    synthesis: String? = nil, fallback: String? = nil, reason: String = "") {
        var lead = lead
        var dedupNote = ""
        if let c = lead, leadCategory == .croupier, Self.oncePerHand.contains(c.rawValue) {
            if oncePerHandPlayed.contains(c.rawValue) {
                lead = nil
                dedupNote = " [deduped]"
            } else {
                oncePerHandPlayed.insert(c.rawValue)
                dedupNote = " [first this hand]"
            }
        }
        guard lead != nil || synthesis != nil || fallback != nil else { return }
        #if DEBUG
        if Self.logging {
            print("[SpeechLog] say lead=\(lead?.rawValue ?? "—") synth=\(synthesis ?? "—") reason=\(reason)\(dedupNote)")
        }
        #endif
        queue.append(Item(lead: lead, leadCategory: leadCategory, synthesis: synthesis, fallback: fallback, reason: reason))
        pump()
    }

    /// Test hook: whether a once-per-hand voice would still be admitted now.
    public func admits(_ id: SoundID) -> Bool {
        !(Self.oncePerHand.contains(id.rawValue) && oncePerHandPlayed.contains(id.rawValue))
    }

    private func pump() {
        guard !isSpeaking, !queue.isEmpty else { return }
        isSpeaking = true
        let item = queue.removeFirst()
        Task { await self.process(item) }
    }

    private func process(_ item: Item) async {
        if let lead = item.lead {
            if audio.isAvailable(lead) {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    audio.play(lead, category: item.leadCategory) { cont.resume() }
                }
            } else if let fallback = item.fallback {
                // The mp3 isn't in the bundle yet → speak the declared fallback (D-030).
                announcer.announce(fallback); synthesisObserver?(fallback)
                await pause(synthesisDuration(for: fallback))
            }
        }
        if let synthesis = item.synthesis {
            announcer.announce(synthesis); synthesisObserver?(synthesis)
            await pause(synthesisDuration(for: synthesis))
        }
        isSpeaking = false
        pump()
    }

    /// A rough spoken-duration estimate so the next item doesn't start over an
    /// ongoing VoiceOver line. Zero when VoiceOver is off (nothing is spoken).
    private func synthesisDuration(for text: String) -> TimeInterval {
        guard announcer.isVoiceOverRunning else { return 0 }
        return max(0.8, Double(text.count) * 0.06)
    }

    private func pause(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
