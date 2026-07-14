// MachiavelliSessionDriverTests.swift
// =====================================================================
// The Machiavelli session driver (D-070/D-071): a MATCH is a scored sequence of hands
// ending at a victory threshold; cards are conserved; scores accumulate correctly; the
// whole match is deterministic given a seed; private hands/draws never leak to
// spectators; the audible-wait thinking events bracket every bot turn; and the
// progressive matchmaker introduces opponents by GAMES PLAYED (never time).

import XCTest
@testable import GameWorld
@testable import GameEngine

final class MachiavelliSessionDriverTests: XCTestCase {

    /// A driver with `count` bot players. Small hands + small budgets + a low threshold
    /// so matches finish fast and deterministically (the engine tests cover full rules).
    private func driver(seed: UInt64?, count: Int = 2, handSize: Int = 4, threshold: Int = 25) -> MachiavelliSessionDriver {
        let roster: [Personality] = [.machiavelliStudent, .machiavelliAdult, .machiavelliProfessor]
        let seats = (0..<count).map { pos in
            MachiavelliSeatAssignment(position: pos, playerID: pos,
                                      provider: MachiavelliBotTurnProvider(
                                        HeuristicMachiavelliBot(personality: roster[pos % roster.count],
                                                                seed: UInt64(pos) * 131 &+ 5,
                                                                budget: .nodes(700))))
        }
        return MachiavelliSessionDriver(capacity: count, seats: seats, handSize: handSize,
                                        victoryThreshold: threshold, seed: seed, turnLimit: 16, handLimit: 20)
    }

    func testAMatchCompletesWithAWinnerAcrossHands() async throws {
        let d = driver(seed: 42)
        let outcome = try await d.playMatch()
        XCTAssertTrue((0..<2).contains(outcome.winnerID))
        XCTAssertGreaterThanOrEqual(outcome.handsPlayed, 1)
        // The winner holds the top cumulative score.
        let top = outcome.finalScores.values.max()!
        XCTAssertEqual(outcome.finalScores[outcome.winnerID], top)
        await d.endSession()
    }

    func testScoresAccumulateAcrossHands() async throws {
        // The cumulative score reported by a hand equals the sum of that hand's score and
        // the prior cumulative — i.e. hands add up correctly.
        let d = driver(seed: 7, threshold: 100000)   // huge threshold → play many hands
        var running: [Int: Int] = [0: 0, 1: 0]
        for _ in 0..<5 {
            let hand = try await d.playHand()
            for (id, pts) in hand.handScores { running[id, default: 0] += pts }
            XCTAssertEqual(hand.cumulativeScores, running, "cumulative = sum of per-hand scores")
        }
        await d.endSession()
    }

    func testCardsAreConservedWithinAHand() async throws {
        let d = driver(seed: 7, threshold: 100000)
        _ = try await d.playHand()
        let inHands = d.players.reduce(0) { $0 + (d.handCount(of: $1.id) ?? 0) }
        XCTAssertEqual(inHands + d.tableCardCount + d.stockCount, MachiavelliConstants.totalCards,
                       "every card is accounted for across hands, table and stock")
        await d.endSession()
    }

    func testDeterministicOverTheWholeMatch() async throws {
        func run(_ seed: UInt64) async throws -> (Int, Int, [Int: Int]) {
            let d = driver(seed: seed)
            let o = try await d.playMatch()
            await d.endSession()
            return (o.winnerID, o.handsPlayed, o.finalScores)
        }
        let a = try await run(2026)
        let b = try await run(2026)
        XCTAssertEqual(a.0, b.0)
        XCTAssertEqual(a.1, b.1)
        XCTAssertEqual(a.2, b.2, "same seed → identical match, hand for hand")
    }

    func testProductionSeedVariesBetweenSessions() async throws {
        func firstHand() async throws -> [Card] {
            let d = MachiavelliSessionDriver(
                capacity: 2,
                seats: [MachiavelliSeatAssignment(position: 0, playerID: 0,
                          provider: MachiavelliBotTurnProvider(HeuristicMachiavelliBot(personality: .machiavelliStudent, seed: 1, budget: .nodes(500)))),
                        MachiavelliSeatAssignment(position: 1, playerID: 1,
                          provider: MachiavelliBotTurnProvider(HeuristicMachiavelliBot(personality: .machiavelliStudent, seed: 2, budget: .nodes(500))))],
                handSize: 5, seed: nil, turnLimit: 4, handLimit: 1)
            let stream = await d.events(as: .player(0))
            async let cards: [Card] = {
                for await event in stream {
                    if case let .privateHand(_, cards) = event.payload { return cards }
                }
                return []
            }()
            _ = try await d.playHand()
            await d.endSession()
            return await cards
        }
        var distinct = Set<String>()
        for _ in 0..<5 { distinct.insert(try await firstHand().map { "\($0)" }.joined()) }
        XCTAssertGreaterThan(distinct.count, 1, "production deals a different shoe each session")
    }

    func testPrivateHandsAndDrawsNeverLeakToSpectators() async throws {
        let d = driver(seed: 11)
        let spectatorStream = await d.events(as: .spectator)
        async let leaked: Bool = {
            for await event in spectatorStream {
                switch event.payload {
                case .privateHand, .privateDraw: return true
                default: break
                }
            }
            return false
        }()
        _ = try await d.playMatch()
        await d.endSession()
        let didLeak = await leaked
        XCTAssertFalse(didLeak, "a spectator never receives any player's private cards")
    }

    func testHandEndedCarriesScoresAndMatchEndedCarriesWinner() async throws {
        let d = driver(seed: 5)
        let stream = await d.events(as: .spectator)
        async let observed: (Bool, Bool) = {
            var sawHandScores = false, sawMatchWinner = false
            for await event in stream {
                switch event.payload {
                case let .handEnded(_, _, handScores, _): if !handScores.isEmpty { sawHandScores = true }
                case .matchEnded: sawMatchWinner = true
                default: break
                }
            }
            return (sawHandScores, sawMatchWinner)
        }()
        _ = try await d.playMatch()
        await d.endSession()
        let (sawHandScores, sawMatchWinner) = await observed
        XCTAssertTrue(sawHandScores, "hand end reports the points awarded")
        XCTAssertTrue(sawMatchWinner, "match end reports the winner")
    }

    func testThinkingEventsBracketEveryBotTurn() async throws {
        let d = driver(seed: 5)
        let stream = await d.events(as: .spectator)
        async let counts: (Int, Int, Bool) = {
            var began = 0, ended = 0, positiveHint = true
            for await event in stream {
                switch event.payload {
                case let .botThinkingBegan(_, expected):
                    began += 1
                    if expected <= .zero { positiveHint = false }
                case .botThinkingEnded:
                    ended += 1
                default: break
                }
            }
            return (began, ended, positiveHint)
        }()
        _ = try await d.playMatch()
        await d.endSession()
        let (began, ended, positiveHint) = await counts
        XCTAssertGreaterThan(began, 0, "the audible-wait event fires for bot turns")
        XCTAssertEqual(began, ended, "every thinking-began is matched by a thinking-ended")
        XCTAssertTrue(positiveHint, "the thinking event carries a positive expected deliberation")
    }

    // MARK: - Progressive matchmaking (keyed on games played, never time — D-070)

    func testMatchmakerReturnsOneOrTwoOpponents() {
        for games in [0, 5, 10, 20, 40] {
            let roster = MachiavelliMatchmaker.opponents(gamesPlayed: games, seed: UInt64(games))
            XCTAssertTrue((1...2).contains(roster.count))
        }
    }

    func testMatchmakerIsDeterministicGivenSeed() {
        let a = MachiavelliMatchmaker.opponents(gamesPlayed: 12, seed: 999)
        let b = MachiavelliMatchmaker.opponents(gamesPlayed: 12, seed: 999)
        XCTAssertEqual(a.map { $0.name }, b.map { $0.name })
    }

    func testEarlyGamesAreDominatedByTheStudentAndSpareTheProfessor() {
        var studentGames = 0, professorAppears = 0
        for seed in UInt64(0)..<300 {
            let roster = MachiavelliMatchmaker.opponents(gamesPlayed: 0, seed: seed)
            if roster.contains(where: { $0.name == Personality.machiavelliStudent.name }) { studentGames += 1 }
            if roster.contains(where: { $0.name == Personality.machiavelliProfessor.name }) { professorAppears += 1 }
        }
        XCTAssertGreaterThan(studentGames, 250, "the earliest games almost always feature the student")
        XCTAssertEqual(professorAppears, 0, "the professor is never met in the very first games")
    }

    func testLateGamesIntroduceTheProfessorIncludingAlone() {
        var professorAppears = 0, professorAlone = 0
        for seed in UInt64(0)..<300 {
            let roster = MachiavelliMatchmaker.opponents(gamesPlayed: 40, seed: seed)
            if roster.contains(where: { $0.name == Personality.machiavelliProfessor.name }) { professorAppears += 1 }
            if roster.count == 1 && roster[0].name == Personality.machiavelliProfessor.name { professorAlone += 1 }
        }
        XCTAssertGreaterThan(professorAppears, 120, "the professor is a regular late in a career")
        XCTAssertGreaterThan(professorAlone, 40, "and sometimes the only opponent")
    }
}
