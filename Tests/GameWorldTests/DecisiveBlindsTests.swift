import XCTest
@testable import GameWorld
import GameEngine

/// The decisive hand doubles the blinds via the driver's additive per-hand override
/// (D-037), without changing the driver structurally.
final class DecisiveBlindsTests: XCTestCase {

    private func bot(_ seed: UInt64) -> BotActionProvider {
        BotActionProvider(HeuristicBot(personality: .conservativeRock, seed: seed, equitySamples: 20))
    }

    private func makeDriver() -> SessionDriver {
        SessionDriver(capacity: 3, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 1000, provider: bot(1)),
            SeatAssignment(position: 1, playerID: 1, chips: 1000, provider: bot(2)),
            SeatAssignment(position: 2, playerID: 2, chips: 1000, provider: bot(3)),
        ], buttonPosition: 0, smallBlind: 10, bigBlind: 20, seed: 42)
    }

    private func handBeganBlinds(_ events: [EventPayload]) -> (small: Int, big: Int)? {
        for e in events {
            if case let .handBegan(_, _, _, _, _, sb, bb, _) = e { return (sb, bb) }
        }
        return nil
    }

    func testOverrideDoublesThisHandsBlinds() async throws {
        let driver = makeDriver()
        let stream = await driver.events(as: .spectator)
        _ = try await driver.playHand(overrideSmallBlind: 20, overrideBigBlind: 40)
        await driver.endSession()
        var events: [EventPayload] = []
        for await e in stream { events.append(e.payload) }
        let blinds = handBeganBlinds(events)
        XCTAssertEqual(blinds?.small, 20)
        XCTAssertEqual(blinds?.big, 40)
    }

    func testWithoutOverrideUsesTheConfiguredBlinds() async throws {
        let driver = makeDriver()
        let stream = await driver.events(as: .spectator)
        _ = try await driver.playHand()
        await driver.endSession()
        var events: [EventPayload] = []
        for await e in stream { events.append(e.payload) }
        let blinds = handBeganBlinds(events)
        XCTAssertEqual(blinds?.small, 10)
        XCTAssertEqual(blinds?.big, 20)
    }
}
