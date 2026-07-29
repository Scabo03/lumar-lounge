// DecisionHandoffTests.swift
// =====================================================================
// D-106 — the defect that kept coming back wearing different faces, and the
// belt installed behind the fix.
//
// THE DEFECT. Every table drains its driver with the same loop: present the
// next narrated event, or offer the human suspension. It chose between the two
// by sampling two independently-updated sources ACROSS a suspension point — the
// event queue synchronously, then `pendingTurn` behind an actor hop — and the
// relay could append what had just happened during that hop. The turn was then
// offered on the stale reading, so the buttons went live over a hand the player
// had not been shown, and because the suspension parks the SAME loop that
// drains the queue, the narration stayed frozen until the player acted. The
// only key that unfroze the interface was another press, and that press was a
// live game action: at blackjack, a real second card.
//
// HOW IT WAS REPRODUCED, honestly stated. It is an ordering race, so no single
// occurrence is deterministic. What IS deterministic is the harness: driving
// real rounds and sampling the invariant at every offered turn triggers it on
// every run, and adding main-actor contention — which is what SwiftUI supplies
// on a device and `swift test` does not — takes it from a few per cent to
// nearly one offer in two. Measured on this host, before the fix:
//
//     quiet host      239–240 offers   10 / 15 / 14 stale   (4.2% / 6.2% / 5.9%)
//     under pressure  240 offers      110 / 96 / 100 stale  (45.8% / 40.0% / 41.7%)
//
// and in every single one of those the hand on the table differed from the hand
// the player was being asked about. After the fix: 0 out of ~1400, both quiet
// and under pressure.

import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine
import Audio

@MainActor
final class DecisionHandoffTests: XCTestCase {

    // MARK: - 1. The reproduction, now the regression guard

    /// Drives real rounds and checks, at EVERY offered decision, that the player
    /// is being shown the hand they are being asked about. Runs under main-actor
    /// contention, which is what made the race land nearly half the time.
    func testATurnIsNeverOfferedOverAHandThePlayerHasNotBeenShown() async throws {
        var offers = 0
        var stale = 0

        for trial in 0..<4 {
            let name = "d106.\(UUID().uuidString)"
            let store = UserDefaults(suiteName: name)!
            let model = BlackjackTableViewModel(seed: UInt64(9000 + trial), fastMode: true,
                                                audio: NullAudioService(),
                                                mode: AppVoiceOverMode(store: store),
                                                rules: .riverwood,
                                                returnLabel: "back")
            let run = Task { await model.run() }
            // The contention a device has and a test host does not.
            let load = Task { @MainActor in
                while !Task.isCancelled {
                    var sink = 0
                    for i in 0..<20_000 { sink &+= i }
                    _ = sink
                    await Task.yield()
                }
            }

            var ticks = 0, decisions = 0
            while ticks < 1200, decisions < 40, model.outcome == nil {
                if model.betBox != nil {
                    model.confirmBet()
                } else if let turn = model.turn {
                    offers += 1
                    let shown = model.state.hands.indices.contains(turn.handIndex)
                        ? model.state.hands[turn.handIndex].cards : []
                    if shown != turn.cards || model.undeliveredCount > 0 { stale += 1 }
                    decisions += 1
                    if turn.legal.allowed.contains(.hit), turn.total < 17 { model.hit() }
                    else { model.stand() }
                }
                try await Task.sleep(nanoseconds: 3_000_000)
                ticks += 1
            }
            run.cancel()
            load.cancel()
        }

        XCTAssertGreaterThan(offers, 100, "the harness must actually exercise many decisions")
        XCTAssertEqual(stale, 0,
                       "\(stale) of \(offers) decisions were offered over a hand the player had not been shown")
    }

    /// The same invariant at a poker table, because the defect was structural: the
    /// identical loop shape lives in all seven view models, so the fix has to hold
    /// somewhere other than the table it was found on.
    func testTheInvariantHoldsAtAPokerTableToo() async throws {
        let name = "d106.texas.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        let model = TableViewModel(seed: 20260728, fastMode: true,
                                   audio: NullAudioService(),
                                   mode: AppVoiceOverMode(store: store),
                                   rules: .classic,
                                   returnLabel: "back")
        let run = Task { await model.run() }
        let load = Task { @MainActor in
            while !Task.isCancelled {
                var sink = 0
                for i in 0..<20_000 { sink &+= i }
                _ = sink
                await Task.yield()
            }
        }

        var offers = 0, stale = 0, ticks = 0
        while ticks < 1500, offers < 30, model.outcome == nil {
            if model.humanTurn != nil {
                offers += 1
                if model.undeliveredCount > 0 || !model.decisionIsShown { stale += 1 }
                model.checkOrCall()
            }
            try await Task.sleep(nanoseconds: 3_000_000)
            ticks += 1
        }
        run.cancel()
        load.cancel()

        XCTAssertGreaterThan(offers, 5, "the harness must actually reach the human's turn")
        XCTAssertEqual(stale, 0, "\(stale) of \(offers) poker turns were offered over undelivered narration")
    }

    // MARK: - 2. The belt's freshness half, from a controlled clock

    /// A first press is NEVER delayed — the floor is measured from the player's
    /// previous action, not from the moment the decision appeared, which is the
    /// whole reason it cannot become a new defect of its own.
    func testTheFirstPressIsNeverHeldBack() {
        var clock: TimeInterval = 100
        let readiness = InputReadiness(settle: 0.35, now: { clock })
        XCTAssertTrue(readiness.isSettled, "with no previous action there is nothing to bounce off")
        clock += 0     // no time passes at all
        XCTAssertTrue(readiness.isSettled)
    }

    /// A bounce is refused; the same press, once a real decision could have been
    /// made, is honoured.
    func testABounceIsRefusedAndASecondDecisionIsHonoured() {
        var clock: TimeInterval = 100
        var readiness = InputReadiness(settle: 0.35, now: { clock })

        readiness.accept()                       // the player acts
        XCTAssertFalse(readiness.isSettled, "an immediate second press is a bounce")
        clock += 0.20
        XCTAssertFalse(readiness.isSettled, "still inside the bounce window")
        clock += 0.20                            // 0.40 total
        XCTAssertTrue(readiness.isSettled, "a deliberate second decision is honoured")

        readiness.reset()
        clock += 0
        XCTAssertTrue(readiness.isSettled, "a fresh sequence has nothing to bounce off")
    }

    // MARK: - 3. The belt, end to end: a bounce cannot draw a card

    /// The reported disaster, as a test: the player presses Carta, and a second
    /// press that lands before they could have learnt anything must NOT draw a
    /// second card — while the same press, once time has genuinely passed, must.
    ///
    /// The clock is injected, so this measures the DISTINCTION rather than
    /// sleeping and hoping.
    func testABouncedPressDrawsNoCardAndARealSecondPressDoes() async throws {
        var clock: TimeInterval = 1000
        var found: BlackjackTableViewModel?
        var runner: Task<Void, Never>?

        // Find a decision where hitting is legal and CANNOT bust (total ≤ 11), so a
        // further decision on the same hand is guaranteed to follow. Several seeds,
        // because which hands are dealt is not the point of this test.
        seeds: for seed in [20260729, 771, 90210, 5150, 31337] {
            let name = "d106.belt.\(UUID().uuidString)"
            let store = UserDefaults(suiteName: name)!
            let candidate = BlackjackTableViewModel(seed: UInt64(seed), fastMode: true,
                                                    audio: NullAudioService(),
                                                    mode: AppVoiceOverMode(store: store),
                                                    rules: .riverwood,
                                                    returnLabel: "back")
            candidate.setInputReadinessForTests(InputReadiness(settle: 0.35, now: { clock }))
            let task = Task { await candidate.run() }

            var ticks = 0
            while ticks < 1500, candidate.outcome == nil {
                if candidate.betBox != nil {
                    candidate.confirmBet()
                } else if let turn = candidate.turn {
                    if turn.legal.allowed.contains(.hit), turn.total <= 11 {
                        found = candidate
                        runner = task
                        break seeds
                    }
                    if turn.legal.allowed.contains(.stand) { candidate.stand() } else { candidate.hit() }
                }
                try await Task.sleep(nanoseconds: 3_000_000)
                ticks += 1
            }
            task.cancel()
        }

        guard let model = found, let run = runner, let first = model.turn else {
            return XCTFail("never reached a decision where hitting cannot bust")
        }
        defer { run.cancel() }
        let handIndex = first.handIndex
        let before = model.state.hands[handIndex].cards.count

        XCTAssertTrue(model.decisionIsShown, "the decision must be fully shown before it is acted on")
        model.hit()                                    // press one: accepted

        // Wait for the next decision on the same hand, with the clock FROZEN — so
        // no time at all has passed for the player.
        var waited = 0
        while model.turn == nil, waited < 300 {
            try await Task.sleep(nanoseconds: 3_000_000)
            waited += 1
        }
        guard model.turn != nil else { return XCTFail("the interface never advanced to the next decision") }
        let afterOne = model.state.hands[handIndex].cards.count
        XCTAssertEqual(afterOne, before + 1, "the first press draws exactly one card")

        // THE BOUNCE: the same button, before the player could have learnt anything.
        model.hit()
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(model.state.hands[handIndex].cards.count, afterOne,
                       "a bounced press must not draw a second card")
        XCTAssertNotNil(model.turn, "and the decision is still there to be answered")

        // THE REAL SECOND DECISION: time passes, the same press is honoured.
        clock += 1.0
        model.hit()
        waited = 0
        while model.state.hands[handIndex].cards.count == afterOne, waited < 300 {
            try await Task.sleep(nanoseconds: 3_000_000)
            waited += 1
        }
        XCTAssertEqual(model.state.hands[handIndex].cards.count, afterOne + 1,
                       "a deliberate second press must be honoured — the belt must not swallow real input")
    }

    // MARK: - 4. Counter-verification: the interface stays responsive

    /// The belt must not make the table sluggish or eat legitimate input: a run of
    /// ordinary, separated decisions must all be honoured and the interface must
    /// keep advancing after each one.
    func testEveryLegitimateDecisionIsHonouredAndTheInterfaceKeepsAdvancing() async throws {
        let name = "d106.responsive.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        let model = BlackjackTableViewModel(seed: 4242, fastMode: true,
                                            audio: NullAudioService(),
                                            mode: AppVoiceOverMode(store: store),
                                            rules: .riverwood,
                                            returnLabel: "back")
        let run = Task { await model.run() }
        defer { run.cancel() }

        var honoured = 0, refused = 0, ticks = 0
        while ticks < 1500, honoured < 25, model.outcome == nil {
            if model.betBox != nil {
                model.confirmBet()
            } else if let turn = model.turn {
                let before = model.state.hands[turn.handIndex].cards.count
                let hitting = turn.legal.allowed.contains(.hit) && turn.total < 17
                if hitting { model.hit() } else { model.stand() }
                // A press is honoured when the decision it answered is taken away.
                if model.turn == nil { honoured += 1 } else { refused += 1 }
                _ = before
            }
            try await Task.sleep(nanoseconds: 3_000_000)
            ticks += 1
        }

        XCTAssertGreaterThanOrEqual(honoured, 20, "the table must keep accepting ordinary decisions")
        XCTAssertEqual(refused, 0, "no ordinary, separated decision may be refused")
    }
}
