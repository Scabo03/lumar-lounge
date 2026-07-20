// BlackjackEndOfRoundTests.swift
// =====================================================================
// D-098: MEASURE, then fix (the user's instruction, and the D-091 lesson).
//
// The report is that the end of a round is "almost entirely broken" — only
// the win/lose sting is heard, not the spoken account of what happened. Two
// hypotheses: the explanation is not GENERATED, or it is generated but the
// next wager box opens over it. This file measures both, at the level that
// actually decides it: what the spoken channel is doing at the instant the
// box opens.

import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine
import Audio

@MainActor
final class BlackjackEndOfRoundTests: XCTestCase {

    private func italian<T>(_ body: () -> T) -> T {
        UIStrings.override = BlackjackLocalizedStrings.italian
        defer { UIStrings.override = nil }
        return body()
    }

    // MARK: - Is the explanation even generated? (content + load)

    /// Every way a hand can end must produce a spoken cause AND result, both
    /// undroppable. This is the content half of the measurement.
    func testEveryEndingCarriesACauseAndAResult() {
        italian {
            // The dealer's play is folded into the settlement line (D-098): the
            // event itself is now silent, and the cause is rendered as a clause.
            XCTAssertEqual(BlackjackSpeechMap.plan(for: .dealerPlayed(
                cards: [Card(.ten, .clubs), Card(.nine, .hearts)], total: 19,
                isSoft: false, didBust: false, hasNatural: false, drew: true)), .silent)
            let cause = BlackjackSpeechMap.dealerClauseText(
                revealed: true, total: 19, isSoft: false, busted: false, natural: false)
            XCTAssertNotNil(cause, "the dealer's total is spoken as the cause")
            XCTAssertTrue(cause!.contains("19"), "the cause names the dealer's total: \(cause!)")

            for outcome in [BlackjackOutcome.win, .lose, .push, .bust, .surrender, .natural] {
                let settled = BlackjackSpeechMap.plan(for: .handSettled(
                    handIndex: 0, handCount: 1, outcome: outcome, total: 18, bet: 20, net: -20))
                let line = BlackjackSpeechMap.text(for: settled.synthesis!)
                XCTAssertFalse(line.isEmpty, "\(outcome) must say what happened")
                XCTAssertEqual(BlackjackSpeechMap.priority(for: settled.synthesis!), .high,
                               "\(outcome) result must never be dropped")
            }
        }
    }

    // MARK: - Does the box open over it? (the decisive timing measurement)

    /// Drives real rounds and samples the spoken channel at the instant the wager
    /// box opens. If the channel still owes speech then, the box is cutting off
    /// the round's own explanation — which is exactly the reported symptom.
    func testTheWagerBoxDoesNotOpenWhileTheChannelStillOwesSpeech() async throws {
        let name = "BlackjackEndOfRoundTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        let model = BlackjackTableViewModel(seed: 20260720, fastMode: true,
                                            audio: NullAudioService(),
                                            mode: AppVoiceOverMode(store: store),
                                            rules: .riverwood,
                                            returnLabel: "back")

        // Force the "listening" path even though no VoiceOver runs under test, so
        // the end-of-round waiting is actually exercised.
        model.forceListeningForTests = true

        var samples: [TimeInterval] = []
        let run = Task { await model.run() }

        // Play a handful of rounds: at each wager box, record what the channel
        // still owes, then bet the minimum and stand every hand.
        for _ in 0..<4 {
            try await waitUntil { model.betBox != nil }
            samples.append(model.spokenChannelRemaining)
            model.confirmBet()
            // Resolve the hand: stand as soon as a move is offered.
            var guards = 0
            while model.betBox == nil, guards < 200 {
                if model.turn != nil { model.stand() }
                try await Task.sleep(nanoseconds: 20_000_000)
                guards += 1
                if model.outcome != nil { break }
            }
            if model.outcome != nil { break }
        }
        run.cancel()

        print("── END-OF-ROUND CHANNEL AT BOX OPEN ──  \(samples.map { String(format: "%.1f", $0) })")

        // The FIRST box (before any round) has nothing behind it. Every LATER box
        // opens after a round that must have been explained: the channel must be
        // essentially quiet.
        for (i, owed) in samples.enumerated() where i > 0 {
            XCTAssertLessThan(owed, 0.5,
                              "round \(i): the box opened while \(owed)s of speech was still owed")
        }
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        var ticks = 0
        while !condition(), ticks < 500 {
            try await Task.sleep(nanoseconds: 20_000_000)
            ticks += 1
        }
        XCTAssertTrue(condition(), "condition never became true")
    }
}
