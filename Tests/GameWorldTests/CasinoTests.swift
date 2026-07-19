import XCTest
@testable import GameWorld
@testable import GameEngine

/// The generalised casino pattern (D-065/D-066): the Riverwood is UNCHANGED, the
/// Skypool is added with three tables on an increasing buy-in scale, and the economic
/// access barrier works with free-play OFF (its state when the flag is removed).
final class CasinoTests: XCTestCase {

    // MARK: - Riverwood unchanged (the most important regression, D-065)

    func testRiverwoodTablesAndBuyInsAreUnchanged() {
        let r = Casinos.riverwood
        XCTAssertEqual(r.id, "riverwood")
        // The ORIGINAL tables, in their original order, still lead the list. Later
        // games are appended after them (blackjack, D-090), so this pins the
        // regression it was written for without freezing the house's growth.
        XCTAssertEqual(Array(r.tables.prefix(3)).map(\.id),
                       ["riverwood.table.classic", "riverwood.table.fast", "riverwood.table.draw"])
        // Same buy-ins and rules as before the generalisation.
        XCTAssertEqual(table(r, "riverwood.table.classic").buyIn, 1000)
        XCTAssertEqual(table(r, "riverwood.table.fast").buyIn, 1000)
        XCTAssertEqual(table(r, "riverwood.table.draw").buyIn, 2000)
        // Same personalities (frontier roster), untouched by the Skypool arrival.
        if case let .texas(rules) = table(r, "riverwood.table.classic").game {
            XCTAssertEqual(rules.personalities, WorldPersonalities.classic)
            XCTAssertFalse(rules.decisiveHandBoost)
        } else { XCTFail("Riverwood classic must be a Texas table") }
        if case let .texas(rules) = table(r, "riverwood.table.fast").game {
            XCTAssertEqual(rules.personalities, WorldPersonalities.fast)
            XCTAssertTrue(rules.decisiveHandBoost)
        } else { XCTFail("Riverwood fast must be a Texas table") }
    }

    // MARK: - Skypool tables + increasing buy-in scale (D-065/D-066)

    func testSkypoolHasThreeTablesWithIncreasingBuyInScale() {
        let s = Casinos.skypool
        XCTAssertEqual(s.id, "skypool")
        XCTAssertEqual(Array(s.tables.prefix(3)).map(\.id),
                       ["skypool.table.fast", "skypool.table.classic", "skypool.table.marble"])
        let fast = table(s, "skypool.table.fast").buyIn
        let classic = table(s, "skypool.table.classic").buyIn
        let marble = table(s, "skypool.table.marble").buyIn
        // Fast cheapest, Classic a little more, Marble (the speciality) sensibly the highest.
        XCTAssertLessThan(fast, classic)
        XCTAssertLessThan(classic, marble)
        // ~5× the corresponding Riverwood Texas table (1000).
        XCTAssertEqual(fast, 5000)
        XCTAssertEqual(classic, 6000)
        XCTAssertEqual(marble, 10000)
        XCTAssertGreaterThanOrEqual(marble, 2 * fast)   // the speciality clearly costs more
    }

    func testMarbleIsAnOmahaTableWithUrbanBotsAndEscalation() {
        guard case let .omaha(rules) = table(Casinos.skypool, "skypool.table.marble").game else {
            return XCTFail("Marble must be an Omaha table")
        }
        XCTAssertEqual(rules.personalities, WorldPersonalities.skypool)
        XCTAssertNotEqual(rules.escalation, .none)   // a session-acceleration schedule (D-064)
    }

    func testSkypoolTexasTablesUseUrbanBots() {
        if case let .texas(rules) = table(Casinos.skypool, "skypool.table.classic").game {
            XCTAssertEqual(rules.personalities, WorldPersonalities.skypool)
        } else { XCTFail("Skypool classic must be a Texas table") }
        if case let .texas(rules) = table(Casinos.skypool, "skypool.table.fast").game {
            XCTAssertEqual(rules.personalities, WorldPersonalities.skypoolFast)
            XCTAssertTrue(rules.decisiveHandBoost)
        } else { XCTFail("Skypool fast must be a Texas table") }
    }

    // MARK: - Economic access with FREE PLAY OFF (the real progression, D-065)

    func testEconomicBarrierWithFreePlayOff() {
        // A fresh 5000-chip wallet can afford exactly the cheapest Skypool table.
        let account = PlayerAccount(store: InMemoryChipsStore(chips: 5000), freePlay: false)
        XCTAssertTrue(account.canAfford(table(Casinos.skypool, "skypool.table.fast").buyIn))    // 5000
        XCTAssertFalse(account.canAfford(table(Casinos.skypool, "skypool.table.classic").buyIn)) // 6000
        XCTAssertFalse(account.canAfford(table(Casinos.skypool, "skypool.table.marble").buyIn))  // 10000
        // Buying in deducts the buy-in.
        XCTAssertTrue(account.buyIn(5000))
        XCTAssertEqual(account.chips, 0)
    }

    func testRegistryContainsTheCasinosInOrder() {
        XCTAssertEqual(Casinos.all.map(\.id), ["riverwood", "skypool", "clocktower"])
        XCTAssertEqual(Casinos.casino(hosting: "skypool.table.marble")?.id, "skypool")
        XCTAssertEqual(Casinos.casino(hosting: "riverwood.table.classic")?.id, "riverwood")
        XCTAssertEqual(Casinos.casino(hosting: "clocktower.table.machiavelli")?.id, "clocktower")
    }

    private func table(_ casino: Casino, _ id: String) -> CasinoTable {
        casino.tables.first { $0.id == id }!
    }
}

extension CasinoTests {

    /// The Skypool "Marble" config drives a real Omaha session end-to-end (D-066): its
    /// urban roster and escalation plug straight into the OmahaSessionDriver.
    func testMarbleConfigDrivesAnOmahaSession() async throws {
        guard case let .omaha(rules) = Casinos.skypool.tables.first(where: { $0.id == "skypool.table.marble" })!.game else {
            return XCTFail("Marble must be Omaha")
        }
        let seats = rules.personalities.enumerated().map { (pos, personality) in
            OmahaSeatAssignment(position: pos, playerID: pos, chips: rules.buyIn,
                                provider: OmahaBotActionProvider(
                                    HeuristicOmahaBot(personality: personality, seed: UInt64(pos) * 101 &+ 9,
                                                      equitySamples: 20)))
        }
        let driver = OmahaSessionDriver(capacity: rules.personalities.count, seats: seats, buttonPosition: 0,
                                        smallBlind: rules.smallBlind, bigBlind: rules.bigBlind,
                                        seed: 2026, escalation: rules.escalation)
        var handsPlayed = 0
        let total0 = rules.buyIn * rules.personalities.count
        for _ in 0..<6 where driver.canDealNextHand {
            let outcome = try await driver.playHand()
            handsPlayed += 1
            XCTAssertEqual(outcome.chipsByPlayer.values.reduce(0, +), total0, "chips conserved")
        }
        await driver.endSession()
        XCTAssertGreaterThan(handsPlayed, 0, "the Marble table plays real hands")
    }
}
