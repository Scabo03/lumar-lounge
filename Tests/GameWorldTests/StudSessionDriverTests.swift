import XCTest
@testable import GameWorld
@testable import GameEngine

/// The Stud session driver (D-077/D-079): chip conservation (the table injects NOTHING but
/// the buy-ins), determinism, private-card routing, and the HOUSE PRIZE — now paid only at
/// cash-out, only on a full-table win.
final class StudSessionDriverTests: XCTestCase {

    /// A driver with `id 0` as the "player" (a bot stand-in) plus bot opponents.
    private func driver(seed: UInt64?, stacks: [Int] = [3000, 3000, 3000],
                        escalation: StakeEscalation = .none) -> StudSessionDriver {
        let roster: [Personality] = [.eagerNovice, WorldPersonalities.clockTowerStudent,
                                     WorldPersonalities.clockTowerProfessor]
        let seats = stacks.enumerated().map { (pos, chips) in
            StudSeatAssignment(position: pos, playerID: pos, chips: chips,
                               provider: StudBotActionProvider(
                                   HeuristicStudBot(personality: roster[pos % roster.count],
                                                    seed: UInt64(pos) * 101 &+ 7, equitySamples: 16)))
        }
        return StudSessionDriver(capacity: stacks.count, seats: seats, ante: 25, bringIn: 25, bet: 50,
                                 seed: seed, escalation: escalation)
    }

    // MARK: - Chip conservation & determinism

    /// The ONLY chips that enter a table are the buy-ins (D-079): across a whole session the
    /// total is invariant — the House Prize never touches a table stack anymore.
    func testTableChipsAlwaysConserved() async throws {
        let d = driver(seed: 42)
        for _ in 0..<12 where d.canDealNextHand {
            let outcome = try await d.playHand()
            XCTAssertEqual(outcome.chipsByPlayer.values.reduce(0, +), 9000,
                           "table chips are exactly the buy-ins — no injection")
        }
        await d.endSession()
    }

    func testDeterministicGivenSeed() async throws {
        func run(_ seed: UInt64) async throws -> [[Int: Int]] {
            let d = driver(seed: seed)
            var chips: [[Int: Int]] = []
            for _ in 0..<8 where d.canDealNextHand { chips.append(try await d.playHand().chipsByPlayer) }
            await d.endSession()
            return chips
        }
        let a = try await run(2026)
        let a2 = try await run(2026)
        let c = try await run(2027)
        XCTAssertEqual(a, a2, "same seed → identical session")
        XCTAssertNotEqual(a, c, "a different seed plays out differently")
    }

    func testProductionSeedIsRandomPerSession() async throws {
        func firstHandChips() async throws -> [Int: Int] {
            let d = driver(seed: nil)
            let outcome = try await d.playHand()
            await d.endSession()
            return outcome.chipsByPlayer
        }
        var distinct = Set<String>()
        for _ in 0..<6 { distinct.insert("\(try await firstHandChips().sorted { $0.key < $1.key })") }
        XCTAssertGreaterThan(distinct.count, 1, "production (nil seed) deals different cards each session")
    }

    // MARK: - House Prize: paid ONLY at cash-out, ONLY on a full-table win (D-079)

    /// The prize condition is pure: beating the table = the player has chips AND every
    /// opponent is out.
    func testBeatTheTablePredicate() {
        XCTAssertTrue(HousePrize.beatTheTable(heroChips: 9000, opponentChips: [0, 0]), "busted both → beat the table")
        XCTAssertFalse(HousePrize.beatTheTable(heroChips: 4500, opponentChips: [0, 4500]), "one opponent alive → no")
        XCTAssertFalse(HousePrize.beatTheTable(heroChips: 5000, opponentChips: [2000, 2000]), "both alive → no")
        XCTAssertFalse(HousePrize.beatTheTable(heroChips: 0, opponentChips: [0, 9000]), "hero busted → no")
        XCTAssertFalse(HousePrize.beatTheTable(heroChips: 3000, opponentChips: []), "no opponents (degenerate) → no")
    }

    /// `cashOut` adds the prize IFF the table was beaten — never otherwise.
    func testCashOutAddsPrizeOnlyOnAFullTableWin() {
        // Beat the table: chips + prize.
        XCTAssertEqual(HousePrize.cashOut(heroChips: 9000, opponentChips: [0, 0], prize: 1500), 10500)
        // Left in strong profit but an opponent is still alive: NO prize.
        XCTAssertEqual(HousePrize.cashOut(heroChips: 6000, opponentChips: [0, 3000], prize: 1500), 6000)
        // Busted out: NO prize.
        XCTAssertEqual(HousePrize.cashOut(heroChips: 0, opponentChips: [0, 9000], prize: 1500), 0)
    }

    /// The full economy round-trip with `DEBUG_FREE_PLAY` OFF (the test that matters, D-079):
    /// buy in from the persistent account, then cash out — the prize reaches the persistent
    /// balance if and only if both opponents were eliminated, and never otherwise.
    func testHousePrizeReachesBalanceOnlyOnFullTableWinFreePlayOff() {
        let prize = HousePrize.clockTowerStud

        // (a) Beat the table (busted both): the prize lands in the persistent balance.
        let winner = PlayerAccount(store: InMemoryChipsStore(chips: 5000), freePlay: false)
        XCTAssertTrue(winner.buyIn(3000)); XCTAssertEqual(winner.chips, 2000)
        winner.cashOut(HousePrize.cashOut(heroChips: 9000, opponentChips: [0, 0], prize: prize))
        XCTAssertEqual(winner.chips, 2000 + 9000 + prize, "beating the table pays the prize to the balance")

        // (b) Stood up in strong profit WITHOUT busting both: no prize, ever.
        let quitter = PlayerAccount(store: InMemoryChipsStore(chips: 5000), freePlay: false)
        XCTAssertTrue(quitter.buyIn(3000))
        quitter.cashOut(HousePrize.cashOut(heroChips: 5500, opponentChips: [0, 2500], prize: prize))
        XCTAssertEqual(quitter.chips, 2000 + 5500, "leaving in profit without beating the table earns no prize")

        // (c) Busted out: no prize.
        let loser = PlayerAccount(store: InMemoryChipsStore(chips: 5000), freePlay: false)
        XCTAssertTrue(loser.buyIn(3000))
        loser.cashOut(HousePrize.cashOut(heroChips: 0, opponentChips: [0, 9000], prize: prize))
        XCTAssertEqual(loser.chips, 2000, "a busted player cashes out nothing")
    }

    /// The prize is a real recognition of the impresa, not a mancia: sized to the buy-in.
    func testPrizeIsCalibratedToTheImpresa() {
        XCTAssertEqual(HousePrize.clockTowerStud, 1500)
        XCTAssertEqual(HousePrize.clockTowerStud, StudTableRules.clockTower.housePrize)
        XCTAssertEqual(HousePrize.clockTowerStud, StudTableRules.clockTower.buyIn / 2, "half a buy-in — a real reward")
    }

    // MARK: - Private routing (D-015)

    func testPrivateDownCardsRoutedToOwnerOnly() async throws {
        let d = driver(seed: 3)
        let mine = await d.events(as: .player(0))
        let spectator = await d.events(as: .spectator)

        var myPrivate = 0
        var spectatorPrivate = 0
        var myUpCards = 0
        let collector = Task {
            async let a: Void = { for await e in mine {
                if case let .privateDownCards(seat, _) = e.payload { XCTAssertEqual(seat, 0); myPrivate += 1 }
                if case .upCardDealt = e.payload { myUpCards += 1 }
            } }()
            async let b: Void = { for await e in spectator {
                if case .privateDownCards = e.payload { spectatorPrivate += 1 }
            } }()
            _ = await (a, b)
        }
        _ = try await d.playHand()
        await d.endSession()
        _ = await collector.result

        XCTAssertGreaterThan(myPrivate, 0, "the player receives its own down cards")
        XCTAssertEqual(spectatorPrivate, 0, "a spectator never receives any private down cards")
        XCTAssertGreaterThanOrEqual(myUpCards, 3, "up cards are public — everyone (incl. the player) sees them")
    }

    // MARK: - Canonical event order for one hand

    func testHandEmitsAntesThirdStreetAndBringIn() async throws {
        let d = driver(seed: 11)
        let spectator = await d.events(as: .spectator)
        var antes = 0, upThird = 0, bringIns = 0, holeDealt = 0
        let collector = Task {
            for await e in spectator {
                switch e.payload {
                case .antePosted: antes += 1
                case let .upCardDealt(_, _, street) where street == .third: upThird += 1
                case .bringInPosted: bringIns += 1
                case .holeCardsDealt: holeDealt += 1
                default: break
                }
            }
        }
        _ = try await d.playHand()
        await d.endSession()
        _ = await collector.result
        XCTAssertEqual(antes, 3, "three antes")
        XCTAssertEqual(upThird, 3, "three third-street up cards")
        XCTAssertEqual(bringIns, 1, "one forced bring-in")
        XCTAssertGreaterThanOrEqual(holeDealt, 3, "three seats got down cards on third street")
    }
}
