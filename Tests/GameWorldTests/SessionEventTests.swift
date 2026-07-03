import XCTest
@testable import GameWorld
import GameEngine

final class SessionEventTests: XCTestCase {

    private func bot(_ personality: Personality, seed: UInt64) -> BotActionProvider {
        BotActionProvider(HeuristicBot(personality: personality, seed: seed, equitySamples: 40))
    }

    /// Drains a stream fully into an array. The caller must end the session
    /// first, so the stream is finished and this returns.
    private func drain(_ stream: AsyncStream<SessionEvent>) async -> [SessionEvent] {
        var events: [SessionEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    private func payloads(_ events: [SessionEvent]) -> [EventPayload] { events.map { $0.payload } }

    // MARK: - Expected events arrive in the right order

    func testHandEventsArriveInCanonicalOrder() async throws {
        let driver = SessionDriver(capacity: 2, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 500, provider: bot(.conservativeRock, seed: 1)),
            SeatAssignment(position: 1, playerID: 1, chips: 500, provider: bot(.hotAggressor, seed: 2)),
        ], buttonPosition: 0, smallBlind: 5, bigBlind: 10, seed: 4242)

        let stream = await driver.events(as: .spectator)
        try await driver.playHand()
        await driver.endSession()
        let events = await drain(stream)

        // Sequence numbers are strictly increasing.
        XCTAssertEqual(events.map { $0.sequence }, Array(events.indices).map { events[$0].sequence })
        for i in 1..<events.count { XCTAssertGreaterThan(events[i].sequence, events[i - 1].sequence) }

        func firstIndex(_ predicate: (EventPayload) -> Bool) -> Int? {
            events.firstIndex { predicate($0.payload) }
        }
        let sessionBegan = firstIndex { if case .sessionBegan = $0 { return true }; return false }
        let handBegan = firstIndex { if case .handBegan = $0 { return true }; return false }
        let firstBlind = firstIndex { if case .blindPosted = $0 { return true }; return false }
        let firstDeal = firstIndex { if case .holeCardsDealt = $0 { return true }; return false }
        let firstAction = firstIndex { if case .playerActed = $0 { return true }; return false }
        let handEnded = firstIndex { if case .handEnded = $0 { return true }; return false }
        let sessionEnded = firstIndex { if case .sessionEnded = $0 { return true }; return false }

        XCTAssertNotNil(sessionBegan)
        XCTAssertNotNil(handEnded)
        // sessionBegan → handBegan → blinds → hole cards → actions → hand end → session end.
        XCTAssertLessThan(sessionBegan!, handBegan!)
        XCTAssertLessThan(handBegan!, firstBlind!)
        XCTAssertLessThan(firstBlind!, firstDeal!)
        XCTAssertLessThan(firstDeal!, firstAction!)
        XCTAssertLessThan(firstAction!, handEnded!)
        XCTAssertLessThan(handEnded!, sessionEnded!)

        // Blinds are posted before any cards are dealt.
        let lastBlind = events.lastIndex { if case .blindPosted = $0.payload { return true }; return false }!
        XCTAssertLessThan(lastBlind, firstDeal!)
    }

    func testStreetsAppearInOrderWhenSeenAtShowdown() async throws {
        // Find a seed whose first hand reaches showdown, then assert flop→turn→river order.
        for seed in UInt64(0)..<40 {
            let driver = SessionDriver(capacity: 2, seats: [
                SeatAssignment(position: 0, playerID: 0, chips: 1000, provider: bot(.hotAggressor, seed: 1)),
                SeatAssignment(position: 1, playerID: 1, chips: 1000, provider: bot(.hotAggressor, seed: 2)),
            ], buttonPosition: 0, smallBlind: 5, bigBlind: 10, seed: seed)
            let stream = await driver.events(as: .spectator)
            let outcome = try await driver.playHand()
            await driver.endSession()
            let events = await drain(stream)

            guard outcome.result.board.count == 5 else { continue } // want a full board

            let streets = events.compactMap { event -> Street? in
                if case .streetOpened(let street, _) = event.payload { return street }
                return nil
            }
            XCTAssertEqual(streets, [.flop, .turn, .river], "Streets must open flop→turn→river (seed \(seed))")
            // The five board cards are exactly flop(3)+turn(1)+river(1), in order.
            let community = events.flatMap { event -> [Card] in
                if case .streetOpened(_, let cards) = event.payload { return cards }
                return []
            }
            XCTAssertEqual(community, outcome.result.board)
            return
        }
        XCTFail("No showdown hand found in the seed range")
    }

    // MARK: - Multiple consumers see the same sequence

    func testMultipleSubscribersReceiveTheSameSequence() async throws {
        let driver = SessionDriver(capacity: 3, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 300, provider: bot(.hotAggressor, seed: 1)),
            SeatAssignment(position: 1, playerID: 1, chips: 300, provider: bot(.eagerNovice, seed: 2)),
            SeatAssignment(position: 2, playerID: 2, chips: 300, provider: bot(.conservativeRock, seed: 3)),
        ], buttonPosition: 0, smallBlind: 5, bigBlind: 10, seed: 77)

        let a = await driver.events(as: .spectator)
        let b = await driver.events(as: .spectator)
        try await driver.run(maxHands: 5)
        await driver.endSession()

        let eventsA = await drain(a)
        let eventsB = await drain(b)
        XCTAssertEqual(eventsA, eventsB)
        XCTAssertFalse(eventsA.isEmpty)
    }

    // MARK: - Privacy of hole cards

    func testPlayerSeesOwnHoleCardsButNeverOthers() async throws {
        let driver = SessionDriver(capacity: 2, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 500, provider: bot(.conservativeRock, seed: 1)),
            SeatAssignment(position: 1, playerID: 1, chips: 500, provider: bot(.conservativeRock, seed: 2)),
        ], buttonPosition: 0, smallBlind: 5, bigBlind: 10, seed: 9)

        let mine = await driver.events(as: .player(0))
        let spectator = await driver.events(as: .spectator)
        try await driver.playHand()
        await driver.endSession()

        let myEvents = await drain(mine)
        let spectatorEvents = await drain(spectator)

        // Player 0 receives its own private hole cards…
        let myPrivate = myEvents.compactMap { event -> Int? in
            if case .privateHoleCards(let seatID, _) = event.payload { return seatID }
            return nil
        }
        XCTAssertEqual(myPrivate, [0], "Player 0 must see exactly its own hole cards")

        // …and the actual two cards are present.
        let myCards = myEvents.compactMap { event -> [Card]? in
            if case .privateHoleCards(0, let cards) = event.payload { return cards }
            return nil
        }.first
        XCTAssertEqual(myCards?.count, 2)

        // The spectator never receives ANY private hole cards.
        let spectatorPrivate = spectatorEvents.contains { event in
            if case .privateHoleCards = event.payload { return true }
            return false
        }
        XCTAssertFalse(spectatorPrivate, "A spectator must never receive private hole cards")

        // But both see the public "seat X received two cards" for every seat.
        let publicDeals = spectatorEvents.compactMap { event -> Int? in
            if case .holeCardsDealt(let seatID) = event.payload { return seatID }
            return nil
        }
        XCTAssertEqual(Set(publicDeals), [0, 1])
    }

    // MARK: - Determinism of the whole event stream

    func testEventStreamIsDeterministic() async throws {
        func recordSession() async throws -> [SessionEvent] {
            let driver = SessionDriver(capacity: 3, seats: [
                SeatAssignment(position: 0, playerID: 0, chips: 400, provider: bot(.conservativeRock, seed: 1)),
                SeatAssignment(position: 1, playerID: 1, chips: 400, provider: bot(.hotAggressor, seed: 2)),
                SeatAssignment(position: 2, playerID: 2, chips: 400, provider: bot(.eagerNovice, seed: 3)),
            ], buttonPosition: 0, smallBlind: 5, bigBlind: 10, seed: 2024)
            let stream = await driver.events(as: .player(2))
            try await driver.run(maxHands: 12)
            await driver.endSession()
            return await drain(stream)
        }
        let first = try await recordSession()
        let second = try await recordSession()
        XCTAssertEqual(first, second, "Same session reproduced must produce the same event stream")
        XCTAssertFalse(first.isEmpty)
    }

    // MARK: - Joins/leaves are narrated between hands

    func testJoinAndBustAreNarrated() async throws {
        let driver = SessionDriver(capacity: 3, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 1000, provider: bot(.hotAggressor, seed: 1)),
            SeatAssignment(position: 1, playerID: 1, chips: 20, provider: bot(.eagerNovice, seed: 2)),
        ], buttonPosition: 0, smallBlind: 5, bigBlind: 10, seed: 3)

        let stream = await driver.events(as: .spectator)
        try await driver.playHand()
        try driver.addPlayer(id: 2, chips: 1000, at: 2, provider: bot(.conservativeRock, seed: 4))
        // Play until the short stack busts or we run out of hands.
        _ = try await driver.run(maxHands: 60)
        await driver.endSession()
        let events = await drain(stream)

        // The newcomer's join is narrated.
        XCTAssertTrue(events.contains { event in
            if case .playerJoined(2, 2, 1000) = event.payload { return true }
            return false
        })
        // At least one bust was narrated for the short stack.
        XCTAssertTrue(events.contains { event in
            if case .playerBusted(1) = event.payload { return true }
            return false
        })
    }
}
