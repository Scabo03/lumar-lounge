import XCTest
@testable import GameWorld
import GameEngine

/// Opens whenever it can, else calls; stands pat. Forces a played deal.
private struct OpenAndCallProvider: DrawActionProvider {
    func provideAction(for context: DrawBotContext) async -> DrawAction {
        if context.legal.canBet { return .bet }
        if context.legal.canCall { return .call }
        return context.legal.canCheck ? .check : .fold
    }
    func provideDiscards(for context: DrawDrawContext) async -> [Card] { [] }
}

/// Never opens (always checks). Forces a pass-and-out.
private struct NeverOpenProvider: DrawActionProvider {
    func provideAction(for context: DrawBotContext) async -> DrawAction {
        context.legal.canCheck ? .check : .fold
    }
    func provideDiscards(for context: DrawDrawContext) async -> [Card] { [] }
}

final class DrawSessionEventTests: XCTestCase {

    private func seats(_ providers: [DrawActionProvider]) -> [DrawSeatAssignment] {
        providers.enumerated().map { DrawSeatAssignment(position: $0.offset, playerID: $0.offset,
                                                        chips: 1000, provider: $0.element) }
    }

    /// Collects every event delivered to `viewer` while `body` runs.
    private func collect(_ driver: DrawSessionDriver, as viewer: EventViewer,
                         _ body: @escaping () async throws -> Void) async throws -> [DrawEventPayload] {
        let stream = await driver.events(as: viewer)
        let task = Task { () -> [DrawEventPayload] in
            var payloads: [DrawEventPayload] = []
            for await event in stream { payloads.append(event.payload) }
            return payloads
        }
        try await body()
        await driver.endSession()
        return await task.value
    }

    private func kindOrder(_ payloads: [DrawEventPayload]) -> [String] {
        payloads.map { kind($0) }
    }

    private func kind(_ p: DrawEventPayload) -> String {
        switch p {
        case .sessionBegan: return "sessionBegan"
        case .sessionEnded: return "sessionEnded"
        case .playerJoined: return "playerJoined"
        case .playerLeft: return "playerLeft"
        case .handBegan: return "handBegan"
        case .antePosted: return "antePosted"
        case .cardsDealt: return "cardsDealt"
        case .privateCards: return "privateCards"
        case .playerActed: return "playerActed"
        case .potOpened: return "potOpened"
        case .passedIn: return "passedIn"
        case .drawPhaseBegan: return "drawPhaseBegan"
        case .playerDrew: return "playerDrew"
        case .privateDrawnCards: return "privateDrawnCards"
        case .secondBetBegan: return "secondBetBegan"
        case .handShown: return "handShown"
        case .openersDisqualified: return "openersDisqualified"
        case .potAwarded: return "potAwarded"
        case .handEnded: return "handEnded"
        case .playerBusted: return "playerBusted"
        }
    }

    // MARK: - Canonical order of a played deal

    func testPlayedDealEmitsCanonicalOrder() async throws {
        let driver = DrawSessionDriver(capacity: 4, seats: seats(
            Array(repeating: OpenAndCallProvider(), count: 4)),
            buttonPosition: 0, ante: 10, smallBet: 20, bigBet: 40, seed: 3)

        let events = try await collect(driver, as: .spectator) {
            _ = try await driver.playHand()
        }
        let order = self.kindOrder(events)

        // Backbone landmarks in order.
        func idx(_ k: String) -> Int { order.firstIndex(of: k) ?? -1 }
        XCTAssertEqual(order.first, "sessionBegan")
        XCTAssertLessThan(idx("sessionBegan"), idx("handBegan"))
        XCTAssertLessThan(idx("handBegan"), idx("antePosted"))
        XCTAssertLessThan(idx("antePosted"), idx("cardsDealt"))
        XCTAssertLessThan(idx("cardsDealt"), idx("playerActed"))
        XCTAssertLessThan(idx("potOpened"), idx("drawPhaseBegan"))
        XCTAssertLessThan(idx("drawPhaseBegan"), idx("playerDrew"))
        XCTAssertLessThan(idx("playerDrew"), idx("secondBetBegan"))
        XCTAssertLessThan(idx("secondBetBegan"), idx("handShown"))
        XCTAssertLessThan(idx("handShown"), idx("potAwarded"))
        XCTAssertLessThan(idx("potAwarded"), idx("handEnded"))
        // Four antes, four deals, four draws.
        XCTAssertEqual(order.filter { $0 == "antePosted" }.count, 4)
        XCTAssertEqual(order.filter { $0 == "cardsDealt" }.count, 4)
        XCTAssertEqual(order.filter { $0 == "playerDrew" }.count, 4)
        // A spectator never receives private cards.
        XCTAssertFalse(order.contains("privateCards"))
        XCTAssertFalse(order.contains("privateDrawnCards"))
    }

    // MARK: - Public/private routing

    func testPlayerViewerReceivesOwnPrivateCardsSpectatorDoesNot() async throws {
        let driver = DrawSessionDriver(capacity: 4, seats: seats(
            Array(repeating: OpenAndCallProvider(), count: 4)),
            buttonPosition: 0, ante: 10, smallBet: 20, bigBet: 40, seed: 6)

        let events = try await collect(driver, as: .player(0)) {
            _ = try await driver.playHand()
        }
        // The player sees exactly its OWN dealt private cards (one privateCards for
        // seat 0), never another seat's.
        let privateDeals = events.compactMap { payload -> Int? in
            if case let .privateCards(seatID, _) = payload { return seatID }
            return nil
        }
        XCTAssertEqual(privateDeals, [0])
        // And its own drawn cards after the exchange.
        let privateDraws = events.compactMap { payload -> Int? in
            if case let .privateDrawnCards(seatID, _) = payload { return seatID }
            return nil
        }
        XCTAssertEqual(privateDraws, [0])
    }

    // MARK: - Pass-and-out ordering

    func testPassedInDealEmitsNoDrawOrShowdown() async throws {
        let driver = DrawSessionDriver(capacity: 4, seats: seats(
            Array(repeating: NeverOpenProvider(), count: 4)),
            buttonPosition: 0, ante: 10, smallBet: 20, bigBet: 40, seed: 9)

        let events = try await collect(driver, as: .spectator) {
            _ = try await driver.playHand()
        }
        let order = self.kindOrder(events)
        XCTAssertTrue(order.contains("passedIn"))
        XCTAssertFalse(order.contains("drawPhaseBegan"))
        XCTAssertFalse(order.contains("handShown"))
        XCTAssertFalse(order.contains("potAwarded"))
        // passedIn precedes handEnded.
        XCTAssertLessThan(order.firstIndex(of: "passedIn")!, order.firstIndex(of: "handEnded")!)
        // The carried pot is reported.
        let carried = events.compactMap { payload -> Int? in
            if case let .passedIn(carriedPot, _) = payload { return carriedPot }
            return nil
        }
        XCTAssertEqual(carried, [40])
    }

    // MARK: - Openers disqualification event

    func testOpenersDisqualifiedIsEmittedWhenABluffOpenReachesShowdown() async throws {
        // Search base seeds for a deal whose opener (first actor) lacks openers:
        // the OpenAndCall provider opens anyway, the rest call → showdown → the
        // opener is disqualified, and the driver narrates it.
        var found = false
        for seed in UInt64(0)..<80 where !found {
            let driver = DrawSessionDriver(capacity: 4, seats: seats(
                Array(repeating: OpenAndCallProvider(), count: 4)),
                buttonPosition: 0, ante: 10, smallBet: 20, bigBet: 40, seed: seed)
            let events = try await collect(driver, as: .spectator) {
                _ = try await driver.playHand()
            }
            if let dqIndex = events.firstIndex(where: {
                if case .openersDisqualified = $0 { return true }; return false
            }) {
                found = true
                let order = self.kindOrder(events)
                // Disqualification is announced after the reveals, around the pot.
                XCTAssertLessThan(order.firstIndex(of: "handShown")!, dqIndex)
                XCTAssertLessThan(dqIndex, order.firstIndex(of: "handEnded")!)
                // potOpened for that deal recorded hasOpeners == false.
                let openedWithout = events.contains {
                    if case let .potOpened(_, hasOpeners) = $0 { return hasOpeners == false }
                    return false
                }
                XCTAssertTrue(openedWithout)
            }
        }
        XCTAssertTrue(found, "expected at least one bluff-open disqualification within the seed range")
    }
}
