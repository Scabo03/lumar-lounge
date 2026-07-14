import XCTest
@testable import GameWorld
@testable import GameEngine

/// The Stud session driver (D-077/D-078): chip conservation, determinism, private-card
/// routing, and the HOUSE PRIZE economy with real chip movement.
final class StudSessionDriverTests: XCTestCase {

    /// A driver with `id 0` as the "player" (a bot stand-in) plus bot opponents.
    private func driver(seed: UInt64?, stacks: [Int] = [3000, 3000, 3000],
                        housePrize: Int = 0, prizeRecipient: Int? = nil,
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
                                 housePrize: housePrize, prizeRecipientID: prizeRecipient,
                                 seed: seed, escalation: escalation)
    }

    // MARK: - Chip conservation & determinism

    func testChipsConservedWithoutPrize() async throws {
        let d = driver(seed: 42)
        for _ in 0..<12 where d.canDealNextHand {
            let outcome = try await d.playHand()
            XCTAssertEqual(outcome.chipsByPlayer.values.reduce(0, +), 9000, "chips conserved (no house prize)")
            XCTAssertEqual(outcome.housePrizeAwarded, 0)
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

    // MARK: - House Prize (D-078)

    /// The house prize is the ONLY chip injection: across a session the total chips grow
    /// by exactly the sum of the prizes awarded, and every prize goes to the recipient.
    func testHousePrizeIsTheOnlyChipInjection() async throws {
        let d = driver(seed: 7, housePrize: 200, prizeRecipient: 0)
        var totalPrizes = 0
        var lastTotal = 9000
        for _ in 0..<30 where d.canDealNextHand {
            let outcome = try await d.playHand()
            totalPrizes += outcome.housePrizeAwarded
            // Each hand the prize is 0 or exactly the flat amount.
            XCTAssertTrue(outcome.housePrizeAwarded == 0 || outcome.housePrizeAwarded == 200)
            // Total chips == starting total + all prizes injected so far.
            XCTAssertEqual(outcome.chipsByPlayer.values.reduce(0, +), 9000 + totalPrizes,
                           "chips grow only by the house prize")
            lastTotal = outcome.chipsByPlayer.values.reduce(0, +)
        }
        await d.endSession()
        XCTAssertGreaterThan(totalPrizes, 0, "over 30 hands the player wins and is paid the prize at least once")
        XCTAssertEqual(lastTotal, 9000 + totalPrizes)
    }

    /// A prize is awarded ONLY on a hand the recipient actually wins.
    func testHousePrizeOnlyWhenRecipientWins() async throws {
        let d = driver(seed: 7, housePrize: 200, prizeRecipient: 0)
        let spectator = await d.events(as: .spectator)

        // Track, per hand, whether seat 0 won a pot and whether a prize fired.
        var prizeHands = 0
        var wonWithoutPrize = 0
        let collector = Task {
            var seatZeroWonThisHand = false
            for await e in spectator {
                switch e.payload {
                case let .potAwarded(_, _, winners): if winners.contains(0) { seatZeroWonThisHand = true }
                case let .housePrizeAwarded(playerID, amount):
                    XCTAssertEqual(playerID, 0); XCTAssertEqual(amount, 200)
                    XCTAssertTrue(seatZeroWonThisHand, "a prize only fires on a hand seat 0 won")
                    prizeHands += 1
                case .handEnded:
                    seatZeroWonThisHand = false
                case .handBegan:
                    seatZeroWonThisHand = false
                default: break
                }
            }
        }
        var awarded = 0
        for _ in 0..<25 where d.canDealNextHand { awarded += try await d.playHand().housePrizeAwarded }
        await d.endSession()
        _ = await collector.result
        XCTAssertEqual(prizeHands, awarded / 200, "one prize event per prize-awarded hand")
    }

    func testNoPrizeWhenDisabled() async throws {
        // Recipient set but prize 0 → never fires; and prize set but no recipient → off.
        for d in [driver(seed: 3, housePrize: 0, prizeRecipient: 0),
                  driver(seed: 3, housePrize: 200, prizeRecipient: nil)] {
            for _ in 0..<10 where d.canDealNextHand {
                let prize = try await d.playHand().housePrizeAwarded
                XCTAssertEqual(prize, 0)
            }
            await d.endSession()
        }
    }

    /// The full economy round-trip with `DEBUG_FREE_PLAY` OFF (the test that matters,
    /// D-078): buy in from the persistent account, play a session in which the player
    /// wins prize hands, cash out the table chips, and confirm the house prize really
    /// reached the persistent balance.
    func testHousePrizeReachesThePersistentBalanceFreePlayOff() async throws {
        let account = PlayerAccount(store: InMemoryChipsStore(chips: 5000), freePlay: false)
        XCTAssertTrue(account.buyIn(3000), "sit down: 5000 → 2000 + 3000 table fiches")
        XCTAssertEqual(account.chips, 2000)

        let d = driver(seed: 7, housePrize: 200, prizeRecipient: 0)
        var totalPrizes = 0
        for _ in 0..<30 where d.canDealNextHand { totalPrizes += try await d.playHand().housePrizeAwarded }
        await d.endSession()

        let heroTableChips = d.chips(of: 0)!
        account.cashOut(heroTableChips)   // stand up: table fiches → persistent chips
        XCTAssertEqual(account.chips, 2000 + heroTableChips, "cash-out returns exactly the table chips")
        XCTAssertGreaterThan(totalPrizes, 0, "the player won prize hands")
        // The prize is baked into the table chips, so it flows straight into the persistent
        // balance when the player stands up — they earned by their intellect (D-078). Across
        // the whole session the total chips at the table grew by exactly the prizes injected.
        let tableTotal = d.players.reduce(0) { $0 + $1.chips }
        XCTAssertEqual(tableTotal, 9000 + totalPrizes,
                       "the only chip injection into the session was the house prize")
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
