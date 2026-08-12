// BlackjackFocusTests.swift
// =====================================================================
// D-109 — VoiceOver focus lands on the hand's TOTAL after the wager box is confirmed.
//
// When the player confirmed the bet, the box vanished but focus stayed stranded on
// the confirm button that no longer existed, so it never landed on the hand total
// (the element that reads the total before the individual cards). The poker tables
// re-land focus via a `focusReturnToken` bumped when a box closes — but their hero
// zone is always present. At blackjack the hand does not exist yet when the box
// closes, so the landing is tied to the DEAL: `dealFocusToken` bumps as each round's
// hand is dealt, and the total element claims focus on that change — EVERY round, not
// only on first appearance (the old constant claim fired once on onAppear and never
// again, stranding the cursor from the second round on).
//
// The re-landing does not truncate speech: it happens in present(.dealt), after the
// SILENT round-begin event and the D-108 pacing has drained the previous round, and
// before the dealer's card is announced — the hand is read in that quiet window.

import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine
import Audio

@MainActor
final class BlackjackFocusTests: XCTestCase {

    /// The deal focus token advances once per round, so focus re-lands on the hand total
    /// after every confirmed wager — not just the first (the stranded-focus defect).
    func testFocusReLandsOnTheHandTotalEveryRound() async throws {
        let store = UserDefaults(suiteName: "d109.\(UUID().uuidString)")!
        let model = BlackjackTableViewModel(seed: 4242, fastMode: true,
                                            audio: NullAudioService(),
                                            mode: AppVoiceOverMode(store: store),
                                            rules: .riverwood, returnLabel: "x")
        XCTAssertEqual(model.dealFocusToken, 0, "no deal has happened yet")
        let run = Task { await model.run() }
        defer { run.cancel() }

        var tokensAtDecision: [Int] = []
        var ticks = 0
        while ticks < 3000, tokensAtDecision.count < 3, model.outcome == nil {
            if model.betBox != nil {
                model.confirmBet()
            } else if let turn = model.turn {
                if !tokensAtDecision.contains(model.dealFocusToken) {
                    tokensAtDecision.append(model.dealFocusToken)
                }
                if turn.legal.allowed.contains(.hit), turn.total < 17 { model.hit() } else { model.stand() }
            }
            try await Task.sleep(nanoseconds: 3_000_000)
            ticks += 1
        }

        XCTAssertGreaterThanOrEqual(tokensAtDecision.count, 3, "the harness must reach several rounds")
        // A DISTINCT token per round: the claim re-fires each deal (the old constant claim
        // would have left this at its first value forever).
        XCTAssertEqual(Set(tokensAtDecision).count, tokensAtDecision.count,
                       "each round deals a fresh focus token, so focus re-lands every round")
        XCTAssertGreaterThanOrEqual(model.dealFocusToken, 3,
                                    "the deal token advances once per round, not once per session")
    }
}
