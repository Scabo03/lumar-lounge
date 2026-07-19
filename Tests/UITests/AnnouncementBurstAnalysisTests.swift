import XCTest
@testable import UI
import GameWorld
import GameEngine
import Audio

/// FASE-analisi (D-032): drives a representative session and measures how VoiceOver
/// SYNTHESIS announcements would pile up on a single serial speaker, to choose the
/// queue strategy (A = strict FIFO, C = FIFO + priority + drop) from real numbers.
/// Prints a report; asserts only that data was produced.
@MainActor
final class AnnouncementBurstAnalysisTests: XCTestCase {

    private enum Prio: String { case high, medium, low }
    private struct Arrival { let t: Double; let prio: Prio; let chars: Int; let text: String }

    private func bot(_ p: Personality, _ s: UInt64) -> BotActionProvider {
        BotActionProvider(HeuristicBot(personality: p, seed: s, equitySamples: 30))
    }

    /// Estimated Italian VoiceOver speaking time for a phrase.
    private func speakTime(_ chars: Int) -> Double { 0.5 + Double(chars) * 0.07 }

    private func session() async throws -> [EventPayload] {
        // Hero (seat 0) + three opponents, so betting rounds have the realistic
        // three-opponent action load.
        let driver = SessionDriver(capacity: 4, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 400, provider: bot(.conservativeRock, 10)),
            SeatAssignment(position: 1, playerID: 1, chips: 400, provider: bot(.eagerNovice, 1)),
            SeatAssignment(position: 2, playerID: 2, chips: 400, provider: bot(.hotAggressor, 3)),
            SeatAssignment(position: 3, playerID: 3, chips: 400, provider: bot(.eagerNovice, 5)),
        ], buttonPosition: 0, smallBlind: 10, bigBlind: 20, seed: 42)
        let stream = await driver.events(as: .spectator)
        _ = try await driver.run(maxHands: 8)
        await driver.endSession()
        var events: [EventPayload] = []
        for await e in stream { events.append(e.payload) }
        return events
    }

    /// Turns the session into the arrival timeline of synthesis announcements, at
    /// the human-paced time each would be posted, with its priority.
    private func arrivals(_ events: [EventPayload]) -> [Arrival] {
        let hero = 0
        let names = [0: "Tu", 1: "giocatore 1", 2: "giocatore 2", 3: "giocatore 3"]
        var out: [Arrival] = []
        var t = 0.0
        for e in events {
            let plan = SpeechMap.plan(for: e, heroSeatID: hero, names: names)
            if let line = plan.synthesis {
                let text = SpeechMap.text(for: line)
                out.append(Arrival(t: t, prio: priority(of: line), chars: text.count, text: text))
            }
            t += Pacing.seconds(for: e)
        }
        return out
    }

    private func priority(of line: SynthLine) -> Prio {
        switch line {
        case .heroCards, .yourTurnContext, .heroWon, .heroNetWin, .splitWon, .sessionWon, .sessionLost: return .high
        case .shown: return .high      // the result of the hand is never dropped (D-085)
        case .otherWon, .opponentAction: return .medium
        case .communityCards: return .low
        case .roleButton: return .high
        }
    }

    func testMeasureBurstBehaviourToChooseStrategy() async throws {
        let events = try await session()
        let arr = arrivals(events)
        XCTAssertFalse(arr.isEmpty)

        // Simulate a single serial speaker: an announcement starts at max(arrival,
        // previous end). Queue depth at each arrival = how many earlier ones haven't
        // finished yet.
        var ends: [Double] = []
        var freeAt = 0.0
        var maxDepth = 0
        var depthsOverTwo = 0
        var maxBurst = 0.0
        var burstStart = 0.0
        var lastEnd = -1.0
        var lagSamples: [Double] = []
        var mediumOrLowWhileHighWaiting = 0

        for (i, a) in arr.enumerated() {
            let start = max(a.t, freeAt)
            let end = start + speakTime(a.chars)
            ends.append(end)
            freeAt = end
            lagSamples.append(start - a.t)                 // how late this one starts

            // Depth = announcements that arrived at/before a.t and end after a.t.
            let depth = arr[0...i].filter { $0.t <= a.t }.enumerated()
                .filter { ends[$0.offset] > a.t }.count
            maxDepth = max(maxDepth, depth)
            if depth > 2 { depthsOverTwo += 1 }

            // Continuous busy period (burst) length.
            if a.t <= lastEnd + 0.01 { /* still bursting */ } else { burstStart = start }
            maxBurst = max(maxBurst, end - burstStart)
            lastEnd = end

            // A high-priority one arriving behind medium/low still speaking.
            if a.prio == .high, start - a.t > 1.0 { mediumOrLowWhileHighWaiting += 1 }
        }

        let avgLag = lagSamples.reduce(0, +) / Double(lagSamples.count)
        let maxLag = lagSamples.max() ?? 0
        let highLate = lagSamples.enumerated().filter { arr[$0.offset].prio == .high && $0.element > 1.0 }.count
        let byPrio = Dictionary(grouping: arr, by: { $0.prio }).mapValues { $0.count }
        let sessionSpan = (arr.last?.t ?? 0)
        let totalSpeech = arr.reduce(0.0) { $0 + speakTime($1.chars) }
        _ = ends; _ = maxBurst; _ = depthsOverTwo; _ = mediumOrLowWhileHighWaiting
        // What strategy C would recover: drop medium/low so only high must be spoken.
        let highSpeech = arr.filter { $0.prio == .high }.reduce(0.0) { $0 + speakTime($1.chars) }

        print("""

        === ANNOUNCEMENT BURST ANALYSIS (D-032) ===
        hands=8  synthesis announcements=\(arr.count)
        by priority: high=\(byPrio[.high] ?? 0) medium=\(byPrio[.medium] ?? 0) low=\(byPrio[.low] ?? 0)
        max queue depth=\(maxDepth)   arrivals with depth>2=\(depthsOverTwo)
        session span=\(String(format: "%.0f", sessionSpan))s  total speech(all)=\(String(format: "%.0f", totalSpeech))s  → saturation=\(String(format: "%.0f%%", totalSpeech / sessionSpan * 100))
        total speech(high only)=\(String(format: "%.0f", highSpeech))s → high-only saturation=\(String(format: "%.0f%%", highSpeech / sessionSpan * 100))
        start lag under strict FIFO (strategy A): avg=\(String(format: "%.1f", avgLag))s  max=\(String(format: "%.1f", maxLag))s
        HIGH-priority announcements delayed >1s by a backlog=\(highLate)
        === END ===

        """)
        XCTAssertGreaterThan(arr.count, 0)
    }
}
