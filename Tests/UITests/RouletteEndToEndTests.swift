// RouletteEndToEndTests.swift
// =====================================================================
// D-103 — the roulette table end to end: real chips through the view model
// (DEBUG_FREE_PLAY OFF), the focus discipline, the spin wait, and subtree
// stability (source guards for what a unit test cannot exercise live).

import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine
import Audio

@MainActor
final class RouletteEndToEndTests: XCTestCase {

    private func model(_ rules: RouletteTableRules = .riverwood, seed: UInt64 = 7,
                       onLeave: @escaping (Int) -> Void = { _ in }) -> RouletteTableViewModel {
        let name = "RouletteE2E.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return RouletteTableViewModel(seed: seed, fastMode: true, audio: NullAudioService(),
                                      mode: AppVoiceOverMode(store: store),
                                      rules: rules, returnLabel: "back", onLeave: onLeave)
    }

    private func waitUntil(_ c: @escaping () -> Bool, _ msg: String = "") async throws {
        var t = 0
        while !c(), t < 400 { try await Task.sleep(nanoseconds: 15_000_000); t += 1 }
        XCTAssertTrue(c(), msg)
    }

    // MARK: - A real spin moves real chips (free play OFF)

    func testConfirmingASpinMovesRealChips() async throws {
        // The outcome is deterministic given the seed: compute the expected settlement.
        var wheel = RouletteWheel(seed: 7)
        let pocket = wheel.spin()
        let expected = RouletteResolver.resolve(bets: [.red: 10, .black: 10], pocket: pocket)

        let m = model(seed: 7)
        let run = Task { await m.run() }
        try await waitUntil({ m.awaitingBets }, "should reach betting")
        let start = m.state.chips
        m.placeMinimum(.red)          // 10
        m.increase(.black)            // 10
        XCTAssertEqual(m.slip.totalStaked, 20)
        m.confirm()
        // Wait for the round to fully complete (chips settled, next composition offered).
        try await waitUntil({ m.state.roundNumber == 1 && m.state.phase == .betting }, "round completes")
        XCTAssertEqual(m.state.chips, start - expected.totalStaked + expected.totalReturned,
                       "chips = start - staked + returned")
        m.requestLeave()
        run.cancel()
    }

    func testZeroRefundReachesTheChipsThroughTheTable() async throws {
        // Find a seed whose first spin is zero.
        var zeroSeed: UInt64?
        for s in UInt64(1)...3000 { var w = RouletteWheel(seed: s); if w.spin() == 0 { zeroSeed = s; break } }
        let seed = try XCTUnwrap(zeroSeed)
        let m = model(seed: seed)
        let run = Task { await m.run() }
        try await waitUntil({ m.awaitingBets })
        let start = m.state.chips
        m.placeMinimum(.red); m.placeMinimum(.even)   // two even-money bets, 20 total
        m.confirm()
        try await waitUntil({ m.state.roundNumber == 1 && m.state.phase == .betting }, "round completes")
        XCTAssertEqual(m.state.chips, start, "zero returns the even-money stakes in full")
        m.requestLeave()
        run.cancel()
    }

    func testLeavingCashesOutTheChipsInHand() async throws {
        var cashedOut: Int?
        let m = model(onLeave: { cashedOut = $0 })
        let run = Task { await m.run() }
        try await waitUntil({ m.awaitingBets })
        m.requestLeave()
        XCTAssertEqual(cashedOut, m.state.chips, "leaving cashes out what is in hand (D-090)")
        run.cancel()
    }

    // MARK: - Focus lands, never stranded (D-092) — source guards

    func testTheFeltAnchorClaimsFocusAfterConfirmAndOutcome() throws {
        let src = try source("RouletteTableView.swift")
        // The felt/status element lands focus on entry and RECLAIMS it on every phase
        // transition (the token the view model bumps after confirm and after the outcome).
        XCTAssertTrue(src.contains("voiceOverFocusLanding()"), "focus lands on entry")
        XCTAssertTrue(src.contains("voiceOverFocusClaim(onChangeOf: model.focusToken)"),
                      "focus reclaims after confirm/outcome")
        // Removing a symbol under the cursor hands focus to the band total.
        XCTAssertTrue(src.contains("voiceOverFocusClaim(onChangeOf: model.slip.bets.count)"),
                      "the band total reclaims focus when a symbol is removed")
    }

    // MARK: - Subtree stability (D-052) — source guard

    func testCellsAreStableLeavesWhoseValueChangesNotTheirStructure() throws {
        let src = try source("RouletteTableView.swift")
        // Each cell is one ignored leaf with an accessibilityValue that changes; there is
        // no `if placed { … } else { … }` swapping the accessible element on state.
        XCTAssertTrue(src.contains(".accessibilityElement(children: .ignore)"))
        XCTAssertTrue(src.contains(".accessibilityValue("))
        XCTAssertTrue(src.contains(".accessibilityAdjustableAction"),
                      "the cell/symbol is adjustable: swipe up/down changes the fiches")
    }

    // MARK: - The spin wait is not a silent freeze (D-103) — source guard

    func testTheSpinWaitFillsTheEarAndIsPreparedForTheRealWheelMp3() throws {
        let vm = try source("RouletteTableViewModel.swift")
        // The "no more bets" croupier cue (informative → synthesis fallback) fills the ear.
        XCTAssertTrue(vm.contains("voRouletteNoMoreBets"))
        XCTAssertTrue(vm.contains("roulette.no.more.bets") || vm.contains("croupier"),
                      "a synthesis fallback speaks when the mp3 is absent")
        // The wait is sized to the real wheel mp3 when present, the short floor when not —
        // so the sound slots in with no teardown.
        XCTAssertTrue(vm.contains("audio.duration(of: SoundCatalog.fxRouletteWheelSpin) ?? RoulettePacing.spinFloor"),
                      "the wait grows to the wheel mp3's duration once it is cabled")
    }

    private func source(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("UI/\(name)"), encoding: .utf8)
    }
}
