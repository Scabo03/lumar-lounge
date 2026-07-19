// BlackjackTests.swift
// =====================================================================
// The rules of the house, exercised at their frontiers.
//
// Most of these situations cannot be reached by shuffling and waiting, so
// the shoe is stacked with a known ordering. The deal order the round uses
// is: player, dealer up, player, dealer down — then draws in sequence.

import XCTest
@testable import GameEngine

final class BlackjackTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a round from an explicit sequence of cards.
    private func round(_ cards: [Card],
                       bet: Int = 100,
                       bankroll: Int = 1000,
                       rules: BlackjackRules = .standard) -> BlackjackRound {
        BlackjackRound(bet: bet, bankroll: bankroll, rules: rules,
                       shoe: Shoe(stacked: cards))
    }

    private func card(_ rank: Rank, _ suit: Suit = .spades) -> Card { Card(rank, suit) }

    // MARK: - Card values and the ace

    func testAceCountsElevenWhenItFitsAndOneWhenItDoesNot() throws {
        // Ace + six is a soft seventeen.
        let soft = BlackjackValue.total([card(.ace), card(.six)])
        XCTAssertEqual(soft.total, 17)
        XCTAssertTrue(soft.isSoft)

        // Adding a ten forces the ace down to one: seventeen, now hard.
        let hard = BlackjackValue.total([card(.ace), card(.six), card(.ten)])
        XCTAssertEqual(hard.total, 17)
        XCTAssertFalse(hard.isSoft)

        // Two aces are eleven plus one, never twenty-two.
        XCTAssertEqual(BlackjackValue.total(of: [card(.ace), card(.ace)]), 12)

        // Face cards are all ten.
        for rank in [Rank.jack, .queen, .king, .ten] {
            XCTAssertEqual(BlackjackValue.points(rank), 10)
        }
    }

    func testSplitIsAboutVALUEnotRank() throws {
        XCTAssertTrue(BlackjackValue.canSplit([card(.king), card(.ten, .hearts)]))
        XCTAssertTrue(BlackjackValue.canSplit([card(.seven), card(.seven, .hearts)]))
        XCTAssertFalse(BlackjackValue.canSplit([card(.nine), card(.ten)]))
    }

    // MARK: - Naturals

    func testNaturalPaysThreeToTwo() throws {
        // Player: ace + king. Dealer: nine + five.
        var r = round([card(.ace), card(.nine), card(.king), card(.five)], bet: 100)
        XCTAssertTrue(r.isComplete, "A natural settles without the player acting.")

        let result = try XCTUnwrap(r.result)
        XCTAssertEqual(result.hands.count, 1)
        XCTAssertEqual(result.hands[0].outcome, .natural)
        XCTAssertEqual(result.hands[0].returned, 250, "100 wager back plus 150 winnings.")
        XCTAssertEqual(result.net, 150)
        XCTAssertFalse(result.dealerPlayed, "The dealer does not draw against a natural.")
        _ = r
    }

    func testOrdinaryTwentyOnePaysEvenMoney() throws {
        // Player: ten + five, hits a six for twenty-one. Dealer: nine + eight (17).
        var r = round([card(.ten), card(.nine), card(.five), card(.eight), card(.six)], bet: 100)
        try? r.apply(.hit)

        let result = try XCTUnwrap(r.result)
        XCTAssertEqual(result.hands[0].total, 21)
        XCTAssertEqual(result.hands[0].outcome, .win, "Twenty-one built by drawing is not a natural.")
        XCTAssertEqual(result.hands[0].returned, 200, "Even money, not three to two.")
    }

    func testNaturalAgainstNaturalIsAPush() throws {
        // Both hold ace + ten.
        var r = round([card(.ace), card(.ace, .hearts), card(.king), card(.queen)], bet: 100)
        let result = try XCTUnwrap(r.result)
        XCTAssertEqual(result.hands[0].outcome, .push)
        XCTAssertEqual(result.hands[0].returned, 100, "The wager comes back untouched.")
        XCTAssertEqual(result.net, 0)
        _ = r
    }

    func testDealerNaturalEndsTheRoundImmediately() throws {
        // Dealer shows an ace over a king; the player holds a plain sixteen.
        var r = round([card(.ten), card(.ace), card(.six), card(.king)], bet: 100)
        XCTAssertTrue(r.isComplete, "The peek ends the round before the player commits more.")

        let result = try XCTUnwrap(r.result)
        XCTAssertTrue(result.dealerHasNatural)
        XCTAssertEqual(result.hands[0].outcome, .lose)
        XCTAssertEqual(result.hands[0].returned, 0)
        _ = r
    }

    // MARK: - Busting and pushing

    func testPlayerBustLosesEvenWhenTheDealerAlsoBusts() throws {
        // Player: ten + six, hits a ten → 26. Dealer: ten + six, would bust too.
        var r = round([card(.ten), card(.ten, .hearts), card(.six), card(.six, .hearts),
                       card(.ten, .clubs), card(.ten, .diamonds)], bet: 100)
        try? r.apply(.hit)

        let result = try XCTUnwrap(r.result)
        XCTAssertEqual(result.hands[0].outcome, .bust)
        XCTAssertEqual(result.hands[0].returned, 0)
        XCTAssertFalse(result.dealerPlayed, "With nothing left to beat, the dealer does not draw.")
    }

    func testDealerBustPaysEveryStandingHand() throws {
        // Player: ten + eight (18), stands. Dealer: ten + six, draws a ten → 26.
        var r = round([card(.ten), card(.ten, .hearts), card(.eight), card(.six),
                       card(.ten, .clubs)], bet: 100)
        try? r.apply(.stand)

        let result = try XCTUnwrap(r.result)
        XCTAssertTrue(result.dealerBusted)
        XCTAssertEqual(result.hands[0].outcome, .win)
        XCTAssertEqual(result.hands[0].returned, 200)
    }

    func testEqualTotalsPush() throws {
        // Both nineteen.
        var r = round([card(.ten), card(.ten, .hearts), card(.nine), card(.nine, .hearts)], bet: 100)
        try? r.apply(.stand)

        let result = try XCTUnwrap(r.result)
        XCTAssertEqual(result.dealerTotal, 19)
        XCTAssertEqual(result.hands[0].outcome, .push)
        XCTAssertEqual(result.net, 0)
    }

    // MARK: - The dealer's own rule

    func testDealerStandsOnSOFTseventeen() throws {
        // Dealer: ace + six — a soft seventeen. The house rule stops there.
        // Player: ten + eight (18), stands and wins.
        var r = round([card(.ten), card(.ace), card(.eight), card(.six),
                       card(.five)], bet: 100)   // the five would be drawn if it hit
        try? r.apply(.stand)

        let result = try XCTUnwrap(r.result)
        XCTAssertEqual(result.dealerCards.count, 2, "The dealer must not draw on a soft seventeen.")
        XCTAssertEqual(result.dealerTotal, 17)
        XCTAssertEqual(result.hands[0].outcome, .win)
    }

    func testDealerDrawsBelowSeventeenAndStopsAtIt() throws {
        // Dealer: nine + five (14) → draws a three (17) → stops.
        var r = round([card(.ten), card(.nine), card(.eight), card(.five),
                       card(.three), card(.ten, .clubs)], bet: 100)
        try? r.apply(.stand)

        let result = try XCTUnwrap(r.result)
        XCTAssertEqual(result.dealerTotal, 17)
        XCTAssertEqual(result.dealerCards.count, 3, "One card taken, then the dealer stands.")
    }

    func testDealerDoesNotStandOnSoftSeventeenWhenTheRuleSaysOtherwise() throws {
        // A guard on the rule FLAG rather than on the house's choice, so the
        // knob is proven to be wired and the house rule is proven to be a choice.
        let hitSoft17 = BlackjackRules(dealerStandsOnSoft17: false)
        var r = round([card(.ten), card(.ace), card(.eight), card(.six), card(.two)],
                      bet: 100, rules: hitSoft17)
        try? r.apply(.stand)

        let result = try XCTUnwrap(r.result)
        XCTAssertEqual(result.dealerCards.count, 3)
        XCTAssertEqual(result.dealerTotal, 19)
    }

    // MARK: - Doubling

    func testDoubleTakesExactlyOneCardAndForcesAStand() throws {
        // Player: five + six (11). Doubles, receives a ten → 21.
        var r = round([card(.five), card(.nine), card(.six), card(.eight),
                       card(.ten), card(.two)], bet: 100, bankroll: 1000)
        try r.apply(.double)

        let result = try XCTUnwrap(r.result)
        XCTAssertEqual(result.hands[0].cards.count, 3, "Exactly one card on a double.")
        XCTAssertEqual(result.hands[0].bet, 200, "The wager is doubled.")
        XCTAssertEqual(result.hands[0].total, 21)
        XCTAssertEqual(result.hands[0].outcome, .win)
        XCTAssertEqual(result.hands[0].returned, 400, "Even money on the doubled wager.")
        XCTAssertEqual(result.net, 200)
    }

    func testDoubleIsRefusedWithoutTheChipsToCoverIt() throws {
        var r = round([card(.five), card(.nine), card(.six), card(.eight), card(.ten)],
                      bet: 100, bankroll: 50)
        let legal = try XCTUnwrap(r.legalActions())
        XCTAssertFalse(legal.canDouble, "Fifty chips cannot cover a hundred-chip double.")
        XCTAssertThrowsError(try r.apply(.double)) { error in
            XCTAssertEqual(error as? BlackjackActionError, .insufficientChips)
        }
    }

    func testDoubleIsGoneOnceTheHandHasBeenHit() throws {
        var r = round([card(.five), card(.nine), card(.six), card(.eight),
                       card(.two), card(.ten)], bet: 100)
        try r.apply(.hit)
        let legal = try XCTUnwrap(r.legalActions())
        XCTAssertFalse(legal.canDouble, "Doubling is an opening move only.")
        XCTAssertFalse(legal.canSurrender)
    }

    // MARK: - Splitting

    func testSplitCreatesTwoHandsEachWithItsOwnWager() throws {
        // Player: eight + eight. Dealer: nine + seven (16, will draw).
        var r = round([card(.eight), card(.nine), card(.eight, .hearts), card(.seven),
                       card(.three),           // to the first split hand  → 11
                       card(.two),             // to the second split hand → 10
                       card(.ten),             // first hand hits  → 21
                       card(.ten, .hearts),    // second hand hits → 20
                       card(.four)], bet: 100, bankroll: 1000)   // dealer draws → 20

        try r.apply(.split)
        XCTAssertEqual(r.hands.count, 2)
        XCTAssertEqual(r.hands[0].bet, 100)
        XCTAssertEqual(r.hands[1].bet, 100)
        XCTAssertEqual(r.totalCommitted, 200, "Splitting commits a second wager.")
        XCTAssertEqual(r.bankroll, 900)

        try r.apply(.hit)    // first hand → 21, resolves on its own, moves on
        try r.apply(.hit)    // second hand → 20, still the player's to keep or push
        try r.apply(.stand)

        let result = try XCTUnwrap(r.result)
        XCTAssertEqual(result.hands.count, 2)
        XCTAssertEqual(result.dealerTotal, 20)
        XCTAssertEqual(result.hands[0].outcome, .win, "21 beats the dealer's 20.")
        XCTAssertEqual(result.hands[1].outcome, .push, "20 ties the dealer's 20.")
        XCTAssertEqual(result.totalWagered, 200)
        XCTAssertEqual(result.net, 100)
    }

    func testDoublingIsAllowedOnAHandProducedByASplit() throws {
        var r = round([card(.eight), card(.nine), card(.eight, .hearts), card(.seven),
                       card(.three),        // first split hand → 11
                       card(.two),          // second split hand → 10
                       card(.ten),          // double card on the first → 21
                       card(.nine, .hearts),// double card on the second → 19
                       card(.four)], bet: 100, bankroll: 1000)

        try r.apply(.split)
        var legal = try XCTUnwrap(r.legalActions())
        XCTAssertTrue(legal.canDouble, "Doubling after a split is allowed by the house.")

        try r.apply(.double)
        legal = try XCTUnwrap(r.legalActions())
        XCTAssertTrue(legal.canDouble)
        try r.apply(.double)

        let result = try XCTUnwrap(r.result)
        XCTAssertEqual(result.totalWagered, 400, "Two hands, both doubled.")
        XCTAssertEqual(result.hands[0].bet, 200)
        XCTAssertEqual(result.hands[1].bet, 200)
    }

    func testSplitAcesTakeOneCardEachAndAreDone() throws {
        // Player: ace + ace. Dealer: nine + seven.
        var r = round([card(.ace), card(.nine), card(.ace, .hearts), card(.seven),
                       card(.king),          // to the first ace  → 21
                       card(.five),          // to the second ace → 16
                       card(.four)], bet: 100, bankroll: 1000)   // dealer draws → 20

        try r.apply(.split)
        XCTAssertTrue(r.isComplete, "Both split aces are finished the moment they are dealt.")

        let result = try XCTUnwrap(r.result)
        XCTAssertEqual(result.hands[0].cards.count, 2)
        XCTAssertEqual(result.hands[1].cards.count, 2)
        XCTAssertEqual(result.hands[0].total, 21)
        XCTAssertFalse(result.hands[0].outcome == .natural,
                       "Twenty-one after a split is an ordinary twenty-one.")
        XCTAssertEqual(result.hands[0].outcome, .win)
        XCTAssertEqual(result.hands[0].returned, 200, "Even money, not three to two.")
        XCTAssertEqual(result.hands[1].outcome, .lose)
    }

    func testSplittingStopsAtFourHands() throws {
        // A shoe that keeps dealing eights: every split hand is splittable
        // again, so only the cap can stop it. (Six decks really do hold
        // repeated cards, so duplicate suits here are honest.)
        var stack = [card(.eight), card(.nine), card(.eight, .hearts), card(.seven)]
        stack += Array(repeating: card(.eight, .clubs), count: 8)
        stack += Array(repeating: card(.ten, .clubs), count: 12)

        var r = round(stack, bet: 100, bankroll: 1000)
        var splits = 0
        while let legal = r.legalActions(), legal.canSplit, splits < 10 {
            try r.apply(.split)
            splits += 1
        }
        XCTAssertEqual(splits, 3, "Three splits, four hands.")
        XCTAssertEqual(r.hands.count, 4)
    }

    // MARK: - Surrender

    func testSurrenderGivesBackHalfTheWager() throws {
        var r = round([card(.ten), card(.nine), card(.six), card(.seven)], bet: 100)
        let legal = try XCTUnwrap(r.legalActions())
        XCTAssertTrue(legal.canSurrender)

        try r.apply(.surrender)
        let result = try XCTUnwrap(r.result)
        XCTAssertEqual(result.hands[0].outcome, .surrender)
        XCTAssertEqual(result.hands[0].returned, 50, "Half the wager comes back.")
        XCTAssertEqual(result.net, -50)
        XCTAssertFalse(result.dealerPlayed)
    }

    func testSurrenderIsNotOfferedAfterASplit() throws {
        var r = round([card(.eight), card(.nine), card(.eight, .hearts), card(.seven),
                       card(.three), card(.two)] + Array(repeating: card(.ten, .clubs), count: 6),
                      bet: 100, bankroll: 1000)
        try r.apply(.split)
        let legal = try XCTUnwrap(r.legalActions())
        XCTAssertFalse(legal.canSurrender)
    }

    // MARK: - Insurance is absent by construction

    func testThereIsNoInsuranceAction() throws {
        // Not a behavioural test but a structural one: the action set is closed,
        // so a future session cannot quietly add a losing bet (D-090).
        let all: Set<BlackjackAction> = [.hit, .stand, .double, .split, .surrender]
        var r = round([card(.ten), card(.ace), card(.six), card(.five)], bet: 100)
        if let legal = r.legalActions() {
            XCTAssertTrue(legal.allowed.isSubset(of: all))
        }
        _ = r
    }

    // MARK: - Determinism

    func testSameSeedProducesTheSameRound() throws {
        func play(seed: UInt64) -> [Card] {
            var r = BlackjackRound(bet: 100, bankroll: 1000,
                                   shoe: Shoe(deckCount: 6, seed: seed))
            while r.legalActions() != nil, r.hands[0].total < 17 {
                try? r.apply(.hit)
            }
            if r.legalActions() != nil { try? r.apply(.stand) }
            return (r.result?.hands.flatMap(\.cards) ?? []) + (r.result?.dealerCards ?? [])
        }
        XCTAssertEqual(play(seed: 4242), play(seed: 4242))
        XCTAssertNotEqual(play(seed: 4242), play(seed: 9999))
    }

    func testTheShoePersistsAndReshufflesAtTheCutCard() throws {
        var shoe = Shoe(deckCount: 6, penetration: 0.75, seed: 7)
        XCTAssertEqual(shoe.capacity, 312)
        XCTAssertFalse(shoe.needsShuffle)

        for _ in 0 ..< 234 { _ = shoe.draw() }        // exactly three quarters
        XCTAssertTrue(shoe.needsShuffle)

        let before = shoe.shuffleCount
        shoe.reshuffle()
        XCTAssertEqual(shoe.count, 312, "A reshuffle restores the whole shoe.")
        XCTAssertFalse(shoe.needsShuffle)
        XCTAssertEqual(shoe.shuffleCount, before + 1)
    }

    func testTheShoeNeverRunsDry() throws {
        var shoe = Shoe(deckCount: 1, seed: 3)
        for _ in 0 ..< 200 { _ = shoe.draw() }        // far past a single deck
        XCTAssertGreaterThan(shoe.count, 0)
    }

    // MARK: - The payout table as a whole

    func testPayoutArithmeticIsExactForEveryOutcome() throws {
        // One place that states, in numbers, what each outcome is worth on a
        // hundred-chip wager — the table a future session can check at a glance.
        let expectations: [(BlackjackOutcome, Int)] = [
            (.natural,   250),   // wager + 3:2
            (.win,       200),   // wager + 1:1
            (.push,      100),   // wager back
            (.lose,        0),
            (.bust,        0),
            (.surrender,  50)    // half the wager
        ]
        for (outcome, expected) in expectations {
            let produced = producedReturn(for: outcome, bet: 100)
            XCTAssertEqual(produced, expected, "\(outcome) should return \(expected)")
        }
    }

    /// Drives a real round into each outcome and reads back what it returned.
    private func producedReturn(for outcome: BlackjackOutcome, bet: Int) -> Int {
        switch outcome {
        case .natural:
            var r = round([card(.ace), card(.nine), card(.king), card(.five)], bet: bet)
            return r.result?.hands[0].returned ?? -1
        case .win:
            var r = round([card(.ten), card(.nine), card(.nine), card(.seven), card(.ten, .clubs)], bet: bet)
            try? r.apply(.stand)
            return r.result?.hands[0].returned ?? -1
        case .push:
            var r = round([card(.ten), card(.ten, .hearts), card(.nine), card(.nine, .hearts)], bet: bet)
            try? r.apply(.stand)
            return r.result?.hands[0].returned ?? -1
        case .lose:
            var r = round([card(.ten), card(.ten, .hearts), card(.seven), card(.nine)], bet: bet)
            try? r.apply(.stand)
            return r.result?.hands[0].returned ?? -1
        case .bust:
            var r = round([card(.ten), card(.ten, .hearts), card(.six), card(.six, .hearts),
                           card(.ten, .clubs)], bet: bet)
            try? r.apply(.hit)
            return r.result?.hands[0].returned ?? -1
        case .surrender:
            var r = round([card(.ten), card(.nine), card(.six), card(.seven)], bet: bet)
            try? r.apply(.surrender)
            return r.result?.hands[0].returned ?? -1
        }
    }
}
