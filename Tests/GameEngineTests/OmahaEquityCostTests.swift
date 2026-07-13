import XCTest
import Foundation
@testable import GameEngine

/// MEASURES the real cost of Omaha equity vs Texas equity (D-063), so the bot's
/// per-decision time stays on par with Texas. Prints timings; asserts a ceiling.
final class OmahaEquityCostTests: XCTestCase {

    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    private func time(_ iterations: Int, _ body: () -> Void) -> Double {
        let start = Date()
        for _ in 0..<iterations { body() }
        return Date().timeIntervalSince(start) / Double(iterations) * 1000.0   // ms per call
    }

    func testMeasureEquityCostOmahaVsTexas() {
        let opponents = 3
        let board = [c(.queen, .hearts), c(.jack, .hearts), c(.five, .spades)]   // flop
        let iter = 20                                                            // enough for a ceiling; keeps CI quick

        let texasHole = [c(.ace, .hearts), c(.king, .hearts)]
        var trng = SeededGenerator(seed: 1)
        let texasMs = time(iter) {
            _ = HandStrength.equity(hole: texasHole, board: board, opponents: opponents, samples: 200, using: &trng)
        }

        let omahaHole = [c(.ace, .hearts), c(.king, .hearts), c(.ten, .diamonds), c(.nine, .clubs)]
        var orng = SeededGenerator(seed: 1)
        let omahaMs = time(iter) {
            _ = OmahaStrength.equity(hole: omahaHole, board: board, opponents: opponents,
                                     samples: HeuristicOmahaBot.defaultEquitySamples, using: &orng)
        }
        var orng2 = SeededGenerator(seed: 1)
        let omaha200Ms = time(iter) {
            _ = OmahaStrength.equity(hole: omahaHole, board: board, opponents: opponents, samples: 200, using: &orng2)
        }

        print("""
        === OMAHA EQUITY COST (D-063, debug build — release is ~15-30× faster) ===
        opponents=\(opponents), flop board
        Texas equity (200 samples): \(String(format: "%.2f", texasMs)) ms/call
        Omaha equity ( 60 samples): \(String(format: "%.2f", omahaMs)) ms/call   [bot default]
        Omaha equity (200 samples): \(String(format: "%.2f", omaha200Ms)) ms/call
        per-sample cost ratio Omaha/Texas ≈ \(String(format: "%.2f", (omaha200Ms)/(texasMs)))×
        ========================================================================
        """)

        // Parity is the point (environment-independent): the Omaha bot's default
        // equity is no slower than a Texas equity call, achieved by running ~⅓ the
        // samples to offset the ~3× per-sample cost.
        XCTAssertLessThan(omahaMs, texasMs * 1.6, "Omaha default equity must be on par with Texas equity")
    }

    func testOmahaBotDecisionOnParWithTexasBot() {
        // Same debug environment: compare a full Omaha bot decision to a full Texas
        // bot decision. Parity (not an absolute ms) is the meaningful guarantee.
        let oseats = [OmahaSeat(id: 0, stack: 1000), OmahaSeat(id: 1, stack: 1000), OmahaSeat(id: 2, stack: 1000)]
        var ohand = OmahaHand(seats: oseats, buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 42)
        try? ohand.apply(.call); try? ohand.apply(.call); try? ohand.apply(.check); try? ohand.apply(.bet(20))
        let octx = OmahaBotContext(actingIn: ohand)!
        let obot = HeuristicOmahaBot(personality: .conservativeRock, seed: 9)
        let omahaMs = time(20) { _ = obot.decide(octx) }

        let tseats = [Seat(id: 0, stack: 1000), Seat(id: 1, stack: 1000), Seat(id: 2, stack: 1000)]
        var thand = HoldemHand(seats: tseats, buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 42)
        try? thand.apply(.call); try? thand.apply(.call); try? thand.apply(.check); try? thand.apply(.bet(20))
        let tctx = BotContext(actingIn: thand)!
        let tbot = HeuristicBot(personality: .conservativeRock, seed: 9, equitySamples: 120)
        let texasMs = time(20) { _ = tbot.decide(tctx) }

        print("=== BOT DECISION PARITY: Omaha \(String(format: "%.2f", omahaMs)) ms vs Texas(120s) \(String(format: "%.2f", texasMs)) ms ===")
        XCTAssertLessThan(omahaMs, texasMs * 2.0, "an Omaha bot decision must be comparable to a Texas one")
    }
}
