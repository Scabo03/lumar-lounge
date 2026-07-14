// MachiavelliSessionDriverTests.swift
// =====================================================================
// The Machiavelli session driver (D-075): a GAME is a SINGLE HAND — whoever goes out
// wins, and the end of the hand is the end of the game (the multi-hand match structure
// of D-071 was removed after the real VoiceOver test, D-075). Cards are conserved; the
// game is deterministic given a seed; private hands/draws never leak to spectators; the
// audible-wait thinking events bracket every bot turn; and the progressive matchmaker
// introduces opponents by GAMES PLAYED (never time).

import XCTest
@testable import GameWorld
@testable import GameEngine

final class MachiavelliSessionDriverTests: XCTestCase {

    /// A driver with `count` bot players. Small hands + small budgets so the single hand
    /// finishes fast and deterministically (the engine tests cover the full rules).
    private func driver(seed: UInt64?, count: Int = 2, handSize: Int = 4) -> MachiavelliSessionDriver {
        let roster: [Personality] = [.machiavelliStudent, .machiavelliAdult, .machiavelliProfessor]
        let seats = (0..<count).map { pos in
            MachiavelliSeatAssignment(position: pos, playerID: pos,
                                      provider: MachiavelliBotTurnProvider(
                                        HeuristicMachiavelliBot(personality: roster[pos % roster.count],
                                                                seed: UInt64(pos) * 131 &+ 5,
                                                                budget: .nodes(700))))
        }
        return MachiavelliSessionDriver(capacity: count, seats: seats, handSize: handSize,
                                        seed: seed, turnLimit: 16)
    }

    func testTheGameEndsWithTheFirstHand() async throws {
        let d = driver(seed: 42)
        let outcome = try await d.playMatch()
        XCTAssertTrue((0..<2).contains(outcome.winnerID))
        XCTAssertEqual(outcome.handsPlayed, 1, "the game is a single hand (D-075)")
        XCTAssertTrue(d.isGameOver)
        await d.endSession()
    }

    func testASecondHandIsRejected() async throws {
        // No accumulation across hands: once the one hand is played, the game is over.
        let d = driver(seed: 7)
        _ = try await d.playHand()
        XCTAssertFalse(d.canDealNextHand)
        var threw = false
        do { _ = try await d.playHand() } catch { threw = true }
        XCTAssertTrue(threw, "a second hand cannot be dealt — the game is one hand")
        await d.endSession()
    }

    func testWhoeverGoesOutWinsTheGame() async throws {
        // If a player goes out, they are the winner (not the highest score, D-075).
        let d = driver(seed: 3, handSize: 6)
        let stream = await d.events(as: .spectator)
        async let outID: Int? = {
            for await event in stream { if case let .playerWentOut(id) = event.payload { return id } }
            return nil
        }()
        let outcome = try await d.playMatch()
        await d.endSession()
        if let wentOut = await outID {
            XCTAssertEqual(outcome.winnerID, wentOut, "the player who goes out wins")
        }
    }

    func testCardsAreConservedWithinTheHand() async throws {
        let d = driver(seed: 7)
        _ = try await d.playHand()
        let inHands = d.players.reduce(0) { $0 + (d.handCount(of: $1.id) ?? 0) }
        XCTAssertEqual(inHands + d.tableCardCount + d.stockCount, MachiavelliConstants.totalCards,
                       "every card is accounted for across hands, table and stock")
        await d.endSession()
    }

    func testDeterministicGivenSeed() async throws {
        func run(_ seed: UInt64) async throws -> (Int, [Int: Int]) {
            let d = driver(seed: seed)
            let o = try await d.playMatch()
            await d.endSession()
            return (o.winnerID, o.finalScores)
        }
        let a = try await run(2026)
        let b = try await run(2026)
        XCTAssertEqual(a.0, b.0)
        XCTAssertEqual(a.1, b.1, "same seed → identical game")
    }

    func testProductionSeedVariesBetweenSessions() async throws {
        func firstHand() async throws -> [Card] {
            let d = MachiavelliSessionDriver(
                capacity: 2,
                seats: [MachiavelliSeatAssignment(position: 0, playerID: 0,
                          provider: MachiavelliBotTurnProvider(HeuristicMachiavelliBot(personality: .machiavelliStudent, seed: 1, budget: .nodes(500)))),
                        MachiavelliSeatAssignment(position: 1, playerID: 1,
                          provider: MachiavelliBotTurnProvider(HeuristicMachiavelliBot(personality: .machiavelliStudent, seed: 2, budget: .nodes(500))))],
                handSize: 5, seed: nil, turnLimit: 4)
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

    func testHandEndedCarriesScoresAndGameEndedCarriesWinner() async throws {
        let d = driver(seed: 5)
        let stream = await d.events(as: .spectator)
        async let observed: (Bool, Bool) = {
            var sawHandScores = false, sawWinner = false
            for await event in stream {
                switch event.payload {
                case let .handEnded(_, _, handScores, _): if !handScores.isEmpty { sawHandScores = true }
                case .matchEnded: sawWinner = true
                default: break
                }
            }
            return (sawHandScores, sawWinner)
        }()
        _ = try await d.playMatch()
        await d.endSession()
        let (sawHandScores, sawWinner) = await observed
        XCTAssertTrue(sawHandScores, "hand end reports the points awarded (for the refund, D-075)")
        XCTAssertTrue(sawWinner, "game end reports the winner")
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
