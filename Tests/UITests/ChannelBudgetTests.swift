// ChannelBudgetTests.swift
// =====================================================================
// D-108 — the spoken-channel budget must drop the GLOBALLY lowest item.
//
// From the Phase-3 device trace: at the flop, the board content (MEDIUM) was
// dropped while two chatter lines (LOW) sat safely in the downstream queue — so
// the player heard "giocatore 2 passa" but not the flop. The budget was MEASURED
// across both stages (conductor + queue, D-085) but ENFORCED per-stage, so a
// valuable item arriving at the conductor was dropped instead of lower-priority
// chatter already in the queue. Now the lower of the two stages' lowest droppable
// is dropped, so chatter always yields to the board.

import XCTest
@testable import UI

@MainActor
final class ChannelBudgetTests: XCTestCase {

    func testChatterInTheQueueIsDroppedBeforeTheBoardAtTheConductor() {
        let audio = RecordingAudioService()
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = true          // items accumulate instead of speaking instantly
        var queueDrops: [String] = []
        queue.dropObserver = { text, _ in queueDrops.append(text) }

        let conductor = SpeechConductor(audio: audio, queue: queue)
        var conductorDrops: [String] = []
        conductor.dropObserver = { text, _ in conductorDrops.append(text) }

        // The queue is full of LOW opponent chatter (first speaking, rest waiting).
        queue.enqueue("giocatore 2 passa", priority: .low)
        queue.enqueue("giocatore 1 passa", priority: .low)
        queue.enqueue("giocatore 3 foulda", priority: .low)

        // The flop lands: MEDIUM board content, pushing the whole channel over budget.
        conductor.say(lead: nil, synthesis: "nove di quadri, otto di picche, asso di picche",
                      priority: .medium, reason: "flop")

        XCTAssertTrue(queueDrops.contains { $0.contains("giocatore") },
                      "chatter (low) is dropped from the queue to make room")
        XCTAssertFalse(conductorDrops.contains { $0.contains("nove di quadri") },
                       "the just-landed board (medium) is NOT dropped in favour of chatter")
    }

    func testAllHighNothingIsDropped() {
        let audio = RecordingAudioService()
        let queue = AnnouncementQueue(); queue.voiceOverOverride = true
        var drops = 0
        queue.dropObserver = { _, _ in drops += 1 }
        let conductor = SpeechConductor(audio: audio, queue: queue)
        conductor.dropObserver = { _, _ in drops += 1 }
        // Several long HIGH lines: over budget, but high is never dropped (D-085 invariant).
        for i in 0..<5 {
            conductor.say(lead: nil, synthesis: "riga alta molto lunga numero \(i) con parecchie parole",
                          priority: .high, reason: "high")
        }
        XCTAssertEqual(drops, 0, "high-priority lines are never dropped, however saturated the channel")
    }
}
