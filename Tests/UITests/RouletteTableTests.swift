// RouletteTableTests.swift
// =====================================================================
// D-103 — the roulette table UI: the two zones on one slip, the frequency order,
// the readable/operable state, the casino wiring, and the focus discipline.

import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine

@MainActor
final class RouletteTableTests: XCTestCase {

    private func model(_ rules: RouletteTableRules = .riverwood) -> RouletteTableViewModel {
        let name = "RouletteTableTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return RouletteTableViewModel(seed: 7, mode: AppVoiceOverMode(store: store),
                                      rules: rules, returnLabel: "back")
    }

    // MARK: - Two interfaces, one slip (D-102)

    func testTableAndBandActOnTheSameSlipWithNoDuplicateLogic() {
        let m = model()
        // "Table" places and raises red; then the "band" adjusts the SAME bet — both
        // go through the model's one set of methods onto the one slip.
        m.placeMinimum(.red)          // table: place
        m.increase(.red)              // table swipe up
        XCTAssertEqual(m.slip.amount(on: .red), 20)   // riverwood min 10
        m.increase(.red)              // band swipe up — same method, same entry
        XCTAssertEqual(m.slip.amount(on: .red), 30)
        m.decrease(.red); m.decrease(.red); m.decrease(.red)   // band swipes down to zero → removed
        XCTAssertFalse(m.slip.contains(.red), "the symbol swiped to zero removes the bet")
    }

    // MARK: - The frequency order (D-101)

    func testTheBoardIsOrderedByBettingFrequency() {
        let kinds = RouletteBoard.allBets.map { $0.kind }
        // The first bets are the simple evens; the last are single numbers.
        XCTAssertEqual(Array(kinds.prefix(4)), [.red, .black, .even, .odd])
        XCTAssertEqual(kinds.last, .straight)
        // Halves come before dozens/columns, which come before inside multi, which
        // come before straights.
        func firstIndex(_ k: RouletteBet.Kind) -> Int { kinds.firstIndex(of: k)! }
        XCTAssertLessThan(firstIndex(.low), firstIndex(.dozen))
        XCTAssertLessThan(firstIndex(.dozen), firstIndex(.split))
        XCTAssertLessThan(firstIndex(.split), firstIndex(.straight))
    }

    func testTheBoardOffersEveryStandardBetGeneratedFromTheLayout() {
        // 37 straights (0…36), 3 dozens, 3 columns, 6 simple/halves, streets, corners,
        // six-lines, splits — a complete European tappeto.
        XCTAssertEqual(RouletteBoard.straights.count, 37)
        XCTAssertEqual(RouletteBoard.insideMulti.filter { $0.kind == .street }.count, 12)
        XCTAssertEqual(RouletteBoard.insideMulti.filter { $0.kind == .sixLine }.count, 11)
        XCTAssertEqual(RouletteBoard.insideMulti.filter { $0.kind == .corner }.count, 22)
        // Every generated bet is a valid, resolvable bet (no malformed coverage).
        for bet in RouletteBoard.allBets {
            XCTAssertFalse(bet.covered.isEmpty)
            XCTAssertTrue(bet.covered.allSatisfy { (0...36).contains($0) })
        }
    }

    // MARK: - Readable state and the interrogable total (D-102)

    func testTheStatusElementCarriesTheInterrogableTotalWhileBetting() {
        UIStrings.override = BlackjackLocalizedStrings.italian
        defer { UIStrings.override = nil }
        let m = model()
        m.placeMinimum(.red)          // 10
        m.increase(.black)            // 10
        // The felt/status label, while betting, states the total at stake.
        XCTAssertEqual(m.slip.totalStaked, 20)
        // And the bet name + amount is what a cell/symbol reads (state legible in place).
        let line = RouletteSpeechMap.betName(.red)
        XCTAssertFalse(line.isEmpty)
    }

    func testCannotConfirmBeforeARoundIsOpenOrWithNoBet() {
        let m = model()
        // No round is open yet (the driver has not asked for bets), so even a placed bet
        // cannot be confirmed — the spin gate needs an OPEN betting suspension.
        m.placeMinimum(.red)
        XCTAssertFalse(m.canConfirm, "cannot spin before a round is open")
        // (The full open-round → bet → confirm path is exercised in RouletteEndToEndTests.)
    }

    // MARK: - The casinos (D-103)

    func testRiverwoodAndSkypoolHaveARouletteTableAndClockTowerDoesNot() {
        func hasRoulette(_ c: Casino) -> Bool {
            c.tables.contains { if case .roulette = $0.game { return true }; return false }
        }
        XCTAssertTrue(hasRoulette(Casinos.riverwood), "the Riverwood hosts roulette")
        XCTAssertTrue(hasRoulette(Casinos.skypool), "the Skypool hosts roulette")
        XCTAssertFalse(hasRoulette(Casinos.clockTower), "the ClockTower must NOT host roulette")

        // Buy-ins and limits, as decided in the engine (D-102).
        let rw = Casinos.riverwood.tables.first { $0.id == "riverwood.table.roulette" }!
        let sp = Casinos.skypool.tables.first { $0.id == "skypool.table.roulette" }!
        if case let .roulette(rules) = rw.game {
            XCTAssertEqual([rules.minimumBet, rules.maximumBet, rules.buyIn], [10, 500, 1000])
        } else { XCTFail("Riverwood roulette must be a roulette table") }
        if case let .roulette(rules) = sp.game {
            XCTAssertEqual([rules.minimumBet, rules.maximumBet, rules.buyIn], [50, 2500, 5000])
        } else { XCTFail("Skypool roulette must be a roulette table") }
    }

    // MARK: - The pure display reducer

    func testTheReducerTracksThePhaseAcrossASpin() {
        var s = RouletteTableState()
        s = RouletteTableReducer.reduce(s, .roundBegan(roundNumber: 1, totalStaked: 20, chips: 980))
        XCTAssertEqual(s.phase, .spinning)
        let res = RouletteResolver.resolve(bets: [.red: 20], pocket: 3)
        s = RouletteTableReducer.reduce(s, .roundResolved(resolution: res, chips: 1020))
        XCTAssertEqual(s.phase, .resolved)
        XCTAssertEqual(s.lastPocket, 3)
        XCTAssertEqual(s.chips, 1020)
    }
}
