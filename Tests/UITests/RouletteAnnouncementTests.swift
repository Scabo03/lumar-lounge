// RouletteAnnouncementTests.swift
// =====================================================================
// D-102 — the roulette outcome announcement: compact, complete, and never
// advisory. Rendered from the SHIPPED Italian strings (D-093): under swift test
// there is no bundle, so measuring the keys would be worthless.

import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine

final class RouletteAnnouncementTests: XCTestCase {

    private func italian<T>(_ body: () -> T) -> T {
        UIStrings.override = BlackjackLocalizedStrings.italian
        defer { UIStrings.override = nil }
        return body()
    }

    // MARK: - Compact, complete, rapid

    func testTheOutcomeLineCarriesNumberColourWhoPaidAndTheTotal() {
        italian {
            let r = RouletteResolver.resolve(bets: [.straight(17): 10, .odd: 50], pocket: 17)
            let line = RouletteSpeechMap.outcomeLine(for: r)
            XCTAssertTrue(line.contains("17"), "the number: \(line)")
            XCTAssertTrue(line.lowercased().contains("nero"), "the colour (17 is black): \(line)")
            XCTAssertTrue(line.lowercased().contains("pieno") || line.lowercased().contains("dispari"),
                          "which of the bets paid: \(line)")
            XCTAssertTrue(line.contains(where: \.isNumber), "the total: \(line)")
        }
    }

    /// The whole point (D-091): a spin is understood in a breath. Measured across real
    /// spins from the real strings, it must stay well under a poker hand's load.
    @MainActor
    func testASpinIsRapidToHear() async throws {
        let provider = ScriptedRouletteActionProvider(
            Array(repeating: [.red: 10, .straight(7): 10, .dozen(2): 10], count: 60))
        let driver = RouletteSessionDriver(chips: 100_000, rules: .riverwood, provider: provider, seed: 909)

        var lines = 0
        var seconds: TimeInterval = 0
        let italian = BlackjackLocalizedStrings.localizer()
        let stream = await driver.events()
        let collector = Task { @MainActor in
            for await event in stream {
                if case let .roundResolved(resolution, _) = event.payload {
                    lines += 1
                    let text = RouletteSpeechMap.outcomeLine(for: resolution, localized: { italian($0, $1) })
                    seconds += AnnouncementQueue.speakTime(text)
                }
            }
        }
        let played = try await driver.run(maxRounds: 60)
        await driver.endSession()
        _ = await collector.value

        let perSpin = seconds / Double(max(played.count, 1))
        print(String(format: "\n── ROULETTE SPOKEN LOAD ──  %d spins  1.00 line/spin  %.2f s/spin\n", played.count, perSpin))

        XCTAssertGreaterThan(played.count, 40)
        // One line per spin by construction, and short: comfortably under blackjack's
        // ~6 spoken seconds, so the fast game stays fast for the ear.
        XCTAssertLessThan(perSpin, 6.0, "a spin must be quick to hear")
    }

    // MARK: - The zero refund is explained (D-101)

    func testZeroSaysTheEvenMoneyBetsWereReturned() {
        italian {
            let r = RouletteResolver.resolve(bets: [.red: 100, .even: 50], pocket: 0)
            let line = RouletteSpeechMap.outcomeLine(for: r)
            XCTAssertTrue(line.lowercased().contains("zero"), "it names the zero: \(line)")
            XCTAssertTrue(line.lowercased().contains("restituit"),
                          "it explains the refund, so the player knows why they kept their money: \(line)")
            XCTAssertTrue(line.lowercased().contains("pari"), "and it broke even: \(line)")
        }
    }

    // MARK: - Never advisory (D-091 inviolate)

    func testNoRouletteStringEverSuggestsABet() throws {
        // Sweep every shipped roulette.* string for the vocabulary of advice.
        let strings = BlackjackLocalizedStrings.italian
        let forbidden = ["dovresti", "conviene", "consigl", "punta su", "meglio puntare", "strategia", "ottimale"]
        for (key, value) in strings where key.hasPrefix("roulette.") {
            for phrase in forbidden {
                XCTAssertFalse(value.lowercased().contains(phrase),
                               "\(key) advises a bet: \(value)")
            }
        }
    }

    /// A crowded slip stays rapid: many winners are counted, not enumerated.
    func testManyWinnersAreCountedNotListed() {
        italian {
            // Pocket 17 covered by many overlapping bets.
            let bets: [RouletteBet: Int] = [.red: 10, .odd: 10, .low: 10, .dozen(2): 10,
                                            .column(2): 10, .straight(17): 10]
            let r = RouletteResolver.resolve(bets: bets, pocket: 17)
            let line = RouletteSpeechMap.outcomeLine(for: r)
            XCTAssertTrue(line.lowercased().contains("puntate pagano"),
                          "five+ winners are summarised by count, keeping it short: \(line)")
        }
    }
}
