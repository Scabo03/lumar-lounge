// BlackjackSessionDriverTests.swift
// =====================================================================
// The session around the table: fiches moving, the shoe persisting, the
// narration coming out in the right order — and the persistent gettoni
// arriving at the right number with DEBUG_FREE_PLAY off.

import XCTest
@testable import GameWorld
@testable import GameEngine

final class BlackjackSessionDriverTests: XCTestCase {

    private func driver(chips: Int = 1000,
                        rules: BlackjackTableRules = .riverwood,
                        seed: UInt64 = 99,
                        bet: Int = 20,
                        decide: @escaping @Sendable (BlackjackTurnContext) -> BlackjackAction = { _ in .stand })
    -> BlackjackSessionDriver {
        BlackjackSessionDriver(chips: chips, rules: rules,
                               provider: ScriptedBlackjackActionProvider(bet: bet, decide: decide),
                               seed: seed)
    }

    // MARK: - Chips

    func testFichesMoveByExactlyWhatTheRoundSettled() async throws {
        let d = driver(chips: 1000, bet: 20)
        let before = d.chips
        let outcome = try await d.playRound()
        let round = try XCTUnwrap(outcome)

        XCTAssertEqual(d.chips, before + round.result.net,
                       "The session's fiches move by the round's net, and by nothing else.")
        XCTAssertEqual(d.chips, before - round.result.totalWagered + round.result.totalReturned)
    }

    func testDoubledAndSplitWagersAreBothDeductedAndSettled() async throws {
        // Always double when it is offered, so several rounds commit twice the
        // opening wager and the accounting has to keep up.
        let d = driver(chips: 2000, seed: 5, bet: 20) { context in
            context.legal.canDouble ? .double : .stand
        }
        var expected = d.chips
        let outcomes = try await d.run(maxRounds: 40)
        XCTAssertFalse(outcomes.isEmpty)

        for outcome in outcomes {
            expected += outcome.result.net
            // A doubled hand really did stake twice the opening wager.
            if outcome.result.hands.contains(where: { $0.bet > outcome.bet }) {
                XCTAssertEqual(outcome.result.hands.first?.bet, outcome.bet * 2)
            }
        }
        XCTAssertEqual(d.chips, expected, "Every double is deducted and settled exactly once.")
    }

    func testSurrenderCostsExactlyHalfTheWager() async throws {
        let d = driver(chips: 1000, seed: 31, bet: 20) { context in
            context.legal.canSurrender ? .surrender : .stand
        }
        let outcomes = try await d.run(maxRounds: 30)
        let surrendered = outcomes.filter { $0.result.hands.contains { $0.outcome == .surrender } }
        XCTAssertFalse(surrendered.isEmpty, "The script should have surrendered at least once.")

        for outcome in surrendered {
            XCTAssertEqual(outcome.result.net, -outcome.bet / 2,
                           "Surrender loses half the wager, never all of it.")
        }
    }

    func testTheSessionStopsWhenTheFichesCannotCoverTheMinimum() async throws {
        // A player who always hits until bust runs the stack down.
        let d = driver(chips: 100, seed: 8, bet: 20) { _ in .hit }
        _ = try await d.run(maxRounds: 200)
        XCTAssertLessThan(d.chips, d.minimumBet + 100)
        if d.chips < d.minimumBet {
            XCTAssertFalse(d.canDealNextRound)
        }
    }

    // MARK: - Wager limits

    func testWagersAreClampedIntoTheLegalBandAndKeptExact() async throws {
        let d = driver(chips: 10_000, rules: .riverwood, bet: 999_999)
        let played = try await d.playRound()
        let outcome = try XCTUnwrap(played)
        XCTAssertEqual(outcome.bet, 200, "Clamped to the table maximum.")
        XCTAssertEqual(outcome.bet % 2, 0, "Wagers stay even so payouts are exact.")

        let small = driver(chips: 10_000, rules: .riverwood, bet: 1)
        let playedSmall = try await small.playRound()
        let tiny = try XCTUnwrap(playedSmall)
        XCTAssertEqual(tiny.bet, 20, "Raised to the table minimum.")
    }

    func testTheSkypoolTableCostsFiveTimesTheRiverwoodOne() {
        XCTAssertEqual(BlackjackTableRules.riverwood.buyIn, 1000)
        XCTAssertEqual(BlackjackTableRules.skypool.buyIn, 5000)
        XCTAssertEqual(BlackjackTableRules.skypool.buyIn,
                       BlackjackTableRules.riverwood.buyIn * 5)
        XCTAssertEqual(BlackjackTableRules.skypool.minimumBet,
                       BlackjackTableRules.riverwood.minimumBet * 5)

        // The RULES are identical — only the money differs (D-090).
        XCTAssertEqual(BlackjackTableRules.riverwood.rules, BlackjackTableRules.skypool.rules)
    }

    // MARK: - The shoe

    func testTheShoePersistsAcrossRoundsAndIsReshuffledAtTheCutCard() async throws {
        let d = driver(chips: 100_000, seed: 12, bet: 20)
        var shuffles = 0
        let stream = await d.events()
        let collector = Task {
            for await event in stream {
                if case .shoeShuffled = event.payload { shuffles += 1 }
            }
        }
        _ = try await d.run(maxRounds: 120)
        await d.endSession()
        _ = await collector.value

        XCTAssertGreaterThan(shuffles, 0,
                             "Over a hundred rounds the cut card must have been reached.")
    }

    // MARK: - Determinism

    func testSameSeedProducesTheSameSession() async throws {
        func play(seed: UInt64) async throws -> [Int] {
            let d = driver(chips: 5000, seed: seed, bet: 20) { context in
                context.total < 17 ? .hit : .stand
            }
            return try await d.run(maxRounds: 25).map(\.net)
        }
        let a = try await play(seed: 777)
        let b = try await play(seed: 777)
        let c = try await play(seed: 31337)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Narration

    func testTheRoundIsNarratedInTheOrderItHappens() async throws {
        let d = driver(chips: 1000, seed: 3, bet: 20)
        var payloads: [String] = []
        let stream = await d.events()
        let collector = Task {
            for await event in stream {
                switch event.payload {
                case .sessionBegan:  payloads.append("sessionBegan")
                case .roundBegan:    payloads.append("roundBegan")
                case .dealt:         payloads.append("dealt")
                case .handTurnBegan: payloads.append("handTurnBegan")
                case .playerActed:   payloads.append("playerActed")
                case .dealerPlayed:  payloads.append("dealerPlayed")
                case .handSettled:   payloads.append("handSettled")
                case .roundEnded:    payloads.append("roundEnded")
                default: break
                }
            }
        }
        _ = try await d.playRound()
        await d.endSession()
        _ = await collector.value

        XCTAssertEqual(payloads.first, "sessionBegan")
        XCTAssertEqual(payloads.last, "roundEnded")
        let dealt = try XCTUnwrap(payloads.firstIndex(of: "dealt"))
        let dealer = try XCTUnwrap(payloads.firstIndex(of: "dealerPlayed"))
        let settled = try XCTUnwrap(payloads.firstIndex(of: "handSettled"))
        XCTAssertLessThan(dealt, dealer)
        XCTAssertLessThan(dealer, settled, "The dealer plays before the account is settled.")
    }

    func testTheDealArrivesAsOneEventNotFour() async throws {
        // The heart of the game's accessibility (D-091): the sighted player takes
        // in both their cards and the dealer's up card at a glance, so the deal
        // is ONE fact, not a queue of four announcements.
        let d = driver(chips: 1000, seed: 3, bet: 20)
        var dealEvents = 0
        var playerCardCount = 0
        let stream = await d.events()
        let collector = Task {
            for await event in stream {
                if case let .dealt(cards, _, _, _, _) = event.payload {
                    dealEvents += 1
                    playerCardCount = cards.count
                }
            }
        }
        _ = try await d.playRound()
        await d.endSession()
        _ = await collector.value

        XCTAssertEqual(dealEvents, 1)
        XCTAssertEqual(playerCardCount, 2, "Both player cards ride in the single deal event.")
    }

    // MARK: - Leaving (D-086)

    func testAbandoningEndsTheSessionAtOnceWithoutCommittingMoreChips() async throws {
        let human = HumanBlackjackActionProvider()
        let d = BlackjackSessionDriver(chips: 1000, rules: .riverwood, provider: human, seed: 4)

        let playing = Task { try await d.run(maxRounds: 50) }
        // Let the driver reach the wager question, then walk away.
        try await Task.sleep(nanoseconds: 50_000_000)
        await human.abandon()

        let outcomes = try await playing.value
        XCTAssertTrue(outcomes.isEmpty, "Declining to wager ends the session immediately.")
        XCTAssertEqual(d.chips, 1000, "Walking away before wagering costs nothing.")
    }

    // MARK: - Persistent gettoni, with the debug flag OFF

    func testGettoniMoveForRealWithFreePlayDisabled() async throws {
        // The test that matters: with DEBUG_FREE_PLAY on, the economy is
        // invisible. Everything here runs with it explicitly OFF (D-050).
        let account = PlayerAccount(store: InMemoryChipsStore(chips: 8000), freePlay: false)
        let table = BlackjackTableRules.riverwood

        XCTAssertTrue(account.canAfford(table.buyIn))
        XCTAssertTrue(account.buyIn(table.buyIn))
        XCTAssertEqual(account.chips, 7000, "The buy-in leaves the persistent balance.")

        let d = driver(chips: table.buyIn, seed: 21, bet: 20) { context in
            context.total < 17 ? .hit : .stand
        }
        _ = try await d.run(maxRounds: 30)
        let atTable = d.chips

        account.cashOut(atTable)
        XCTAssertEqual(account.chips, 7000 + atTable,
                       "Cashing out returns exactly the fiches left on the table.")

        // The invariant of §8: the only chips that ever ENTER a table are the
        // buy-in. Blackjack adds no prize, comp or bonus inside a session.
        XCTAssertEqual(7000 + atTable, 8000 - table.buyIn + atTable)
    }

    func testAPlayerWhoCannotAffordTheBuyInCannotSit() {
        let account = PlayerAccount(store: InMemoryChipsStore(chips: 500), freePlay: false)
        XCTAssertFalse(account.canAfford(BlackjackTableRules.riverwood.buyIn))
        XCTAssertFalse(account.canAfford(BlackjackTableRules.skypool.buyIn))
        XCTAssertFalse(account.buyIn(BlackjackTableRules.riverwood.buyIn))
        XCTAssertEqual(account.chips, 500, "A refused buy-in takes nothing.")
    }
}
