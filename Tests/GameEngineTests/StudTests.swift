import XCTest
@testable import GameEngine

/// Seven-Card Stud Pot Limit engine: the canonical rules across the five streets, the
/// bring-in and showing ordering, the Pot Limit cap and side pots, deck exhaustion,
/// and determinism (D-077).
final class StudTests: XCTestCase {

    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    private func freshHand(stacks: [Int] = [3000, 3000, 3000], seed: UInt64 = 1,
                           ante: Int = 25, bringIn: Int = 25, bet: Int = 50) -> StudHand {
        let seats = stacks.enumerated().map { StudSeat(id: $0.offset, stack: $0.element) }
        return StudHand(seats: seats, ante: ante, bringIn: bringIn, bet: bet, seed: seed)
    }

    /// Drives a hand to completion with a per-turn strategy.
    @discardableResult
    private func playOut(_ hand: inout StudHand,
                         _ strategy: (StudLegalActions, StudHand) -> StudAction) -> StudResult {
        var guardCount = 0
        while !hand.isComplete {
            guardCount += 1
            XCTAssertLessThan(guardCount, 5000, "runaway hand")
            guard let legal = hand.legalActions() else { break }
            try? hand.apply(strategy(legal, hand))
        }
        return hand.result!
    }

    /// Passive strategy: never raise, never fold — reaches showdown with everyone in.
    private func passive(_ legal: StudLegalActions, _ hand: StudHand) -> StudAction {
        if legal.canCheck { return .check }
        if legal.canCall { return .call }
        return .fold
    }

    // MARK: - Setup: antes, third-street deal, bring-in

    func testAntesAndThirdStreetDeal() {
        let hand = freshHand()
        // Every seat anted 25 and holds 2 down + 1 up.
        for seat in hand.seats {
            XCTAssertEqual(seat.holeCards.count, 2, "two down cards on third street")
            XCTAssertEqual(seat.upCards.count, 1, "one up card on third street")
            XCTAssertEqual(seat.totalBet - seat.streetBet, 25, "each seat anted 25")
        }
        // Pot so far = 3 antes + the bring-in.
        let pot = hand.seats.reduce(0) { $0 + $1.totalBet }
        XCTAssertEqual(pot, 75 + hand.bringIn)
        XCTAssertEqual(hand.street, .third)
    }

    /// The lowest up card (rank, then clubs-lowest suit) posts the bring-in.
    func testBringInGoesToLowestUpCard() {
        for seed: UInt64 in 1...40 {
            let hand = freshHand(seed: seed)
            let bringInSeat = hand.seats.enumerated().min { a, b in
                let x = a.element.upCards[0], y = b.element.upCards[0]
                if x.rank.rawValue != y.rank.rawValue { return x.rank.rawValue < y.rank.rawValue }
                return StudShowing.bringInSuitOrder(x.suit) < StudShowing.bringInSuitOrder(y.suit)
            }!
            // The bring-in seat committed exactly the bring-in on this street.
            XCTAssertEqual(hand.seats[bringInSeat.offset].streetBet, min(hand.bringIn, 3000 - 25),
                           "seed \(seed): the lowest up card brought in")
            // All others have posted nothing this street yet.
            for (i, seat) in hand.seats.enumerated() where i != bringInSeat.offset {
                XCTAssertEqual(seat.streetBet, 0, "seed \(seed): non-bring-in seat has bet nothing")
            }
        }
    }

    func testBringInSuitOrderIsClubsLowest() {
        XCTAssertTrue(StudShowing.bringInSuitOrder(.clubs) < StudShowing.bringInSuitOrder(.diamonds))
        XCTAssertTrue(StudShowing.bringInSuitOrder(.diamonds) < StudShowing.bringInSuitOrder(.hearts))
        XCTAssertTrue(StudShowing.bringInSuitOrder(.hearts) < StudShowing.bringInSuitOrder(.spades))
    }

    // MARK: - Showing-hand ordering (first to act on later streets)

    func testShowingKeyOrdersMadeHands() {
        let pairAces = [c(.ace, .spades), c(.ace, .hearts)]
        let pairKings = [c(.king, .spades), c(.king, .hearts)]
        let highAce = [c(.ace, .spades), c(.nine, .hearts)]
        let trips = [c(.five, .spades), c(.five, .hearts), c(.five, .diamonds)]
        XCTAssertTrue(StudShowing.isGreater(StudShowing.showingKey(pairAces), than: StudShowing.showingKey(pairKings)))
        XCTAssertTrue(StudShowing.isGreater(StudShowing.showingKey(pairKings), than: StudShowing.showingKey(highAce)))
        XCTAssertTrue(StudShowing.isGreater(StudShowing.showingKey(trips), than: StudShowing.showingKey(pairAces)))
    }

    /// On fourth street the highest board showing acts first.
    func testHighestShowingActsFirstOnFourthStreet() {
        var hand = freshHand()
        // Get through third street: everyone just calls / checks to open fourth.
        while hand.street == .third && !hand.isComplete {
            guard let legal = hand.legalActions() else { break }
            try? hand.apply(passive(legal, hand))
        }
        guard !hand.isComplete, hand.street == .fourth, let actingID = hand.actingSeatID else {
            return   // hand ended early (fine for some seeds); nothing to assert
        }
        // The acting seat must have the highest showing key among non-folded seats.
        let actingKey = StudShowing.showingKey(hand.seats.first { $0.id == actingID }!.upCards)
        for seat in hand.seats where !seat.hasFolded && seat.id != actingID {
            XCTAssertFalse(StudShowing.isGreater(StudShowing.showingKey(seat.upCards), than: actingKey),
                           "the first actor on fourth street holds the highest board")
        }
    }

    // MARK: - Bring-in completion mechanics

    func testCompletionRaisesToTheFullBet() {
        var hand = freshHand(ante: 25, bringIn: 25, bet: 50)
        let legal = hand.legalActions()!
        // Facing only the bring-in (25), the minimum raise is the completion to the full
        // bet (50), not bring-in + a full increment.
        XCTAssertEqual(hand.currentBet, 25)
        XCTAssertEqual(legal.minRaiseTo, 50, "the minimum raise on an uncompleted bring-in is the completion")
        try! hand.apply(.raise(50))
        XCTAssertEqual(hand.currentBet, 50, "completing sets the bet to a full bet")
        // A subsequent raise must now be a full bet on top → to 100.
        let next = hand.legalActions()!
        XCTAssertEqual(next.minRaiseTo, 100, "after completion the minimum re-raise is a full bet more")
    }

    // MARK: - Pot Limit cap in the engine

    func testPotLimitOpeningBetOnFourthStreetEqualsPot() {
        var hand = freshHand()
        while hand.street == .third && !hand.isComplete {
            guard let legal = hand.legalActions() else { break }
            try? hand.apply(passive(legal, hand))
        }
        guard !hand.isComplete, hand.street == .fourth, let legal = hand.legalActions(), legal.canBet else { return }
        let pot = hand.seats.reduce(0) { $0 + $1.totalBet }
        XCTAssertEqual(legal.maxBetTo, min(pot, legal.maxBetTo))
        XCTAssertEqual(legal.maxBetTo, pot, "the pot-limit opening bet equals the pot (stack permitting)")
    }

    // MARK: - Side pots via all-in

    func testShortStackAllInFormsSidePots() {
        var hand = freshHand(stacks: [200, 3000, 3000], seed: 7)
        let result = playOut(&hand) { legal, _ in .allIn }
        // Everyone shoved with different stacks → at least a main pot and a side pot.
        XCTAssertGreaterThanOrEqual(result.pots.count, 2, "unequal all-ins form side pots")
        // Chips are conserved: total final stacks == total starting stacks.
        let finalTotal = result.finalStacks.values.reduce(0, +)
        XCTAssertEqual(finalTotal, 200 + 3000 + 3000, "chips conserved through all-in side pots")
        // The short stack can only win up to what everyone matched of its contribution.
        XCTAssertLessThanOrEqual(result.finalStacks[0]!, 200 * 3, "short stack can't win more than the main pot")
    }

    // MARK: - Full hand & chip conservation

    func testPassiveHandReachesShowdownAndConservesChips() {
        var hand = freshHand(seed: 3)
        let result = playOut(&hand, passive)
        XCTAssertTrue(result.wentToShowdown, "everyone calling reaches showdown")
        // Everyone still in shows seven cards; the winner's best-five is a valid rank.
        for (_, cards) in result.shownHands { XCTAssertEqual(cards.count, 7, "seven cards at showdown") }
        let finalTotal = result.finalStacks.values.reduce(0, +)
        XCTAssertEqual(finalTotal, 3 * 3000, "chips conserved to showdown")
        // The pot went to whoever has the best five of seven.
        let winnerID = result.payouts.max { $0.value < $1.value }!.key
        XCTAssertEqual(result.bestHands[winnerID], result.bestHands.values.max(), "best hand wins")
    }

    func testFoldOutWinsWithoutShowdown() {
        var hand = freshHand(seed: 5)
        // Fold whenever facing a bet; otherwise check. Everyone folds to the bring-in seat.
        let result = playOut(&hand) { legal, _ in
            if legal.canCheck { return .check }
            return .fold
        }
        XCTAssertFalse(result.wentToShowdown, "a fold-out has no showdown")
        XCTAssertEqual(result.payouts.count, 1, "exactly one winner on a fold-out")
        let finalTotal = result.finalStacks.values.reduce(0, +)
        XCTAssertEqual(finalTotal, 3 * 3000, "chips conserved on a fold-out")
    }

    // MARK: - Determinism

    func testDeterministicGivenSeedAndActions() {
        var a = freshHand(seed: 42)
        var b = freshHand(seed: 42)
        let ra = playOut(&a, passive)
        let rb = playOut(&b, passive)
        XCTAssertEqual(ra.finalStacks, rb.finalStacks, "same seed + same actions → identical outcome")
        XCTAssertEqual(ra.wentToShowdown, rb.wentToShowdown)
    }

    // MARK: - Deck exhaustion → community card (D-077)

    func testDeckExhaustionDealsACommunityCardOnSeventhStreet() {
        // Eight players × 7 cards = 56 > 52: the seventh street can't deal everyone a
        // down card, so a single shared community card is dealt.
        var hand = StudHand(seats: (0..<8).map { StudSeat(id: $0, stack: 3000) },
                            ante: 25, bringIn: 25, bet: 50, seed: 11)
        let result = playOut(&hand, passive)
        XCTAssertTrue(result.wentToShowdown)
        XCTAssertNotNil(hand.communityCard, "the deck ran out → one shared community card")
        // Every player who reached the river holds it as their seventh card.
        for (_, cards) in result.shownHands {
            XCTAssertEqual(cards.count, 7, "each showdown hand has seven cards")
            XCTAssertTrue(cards.contains(hand.communityCard!), "everyone shares the community card")
        }
    }

    // MARK: - Illegal actions are rejected

    func testIllegalActionsRejected() {
        var hand = freshHand()
        // Cannot check facing the bring-in.
        XCTAssertThrowsError(try hand.apply(.check))
        // Cannot bet when there is already a bet (the bring-in).
        XCTAssertThrowsError(try hand.apply(.bet(50)))
        // A raise above the pot-limit cap is rejected.
        let legal = hand.legalActions()!
        XCTAssertThrowsError(try hand.apply(.raise(legal.maxRaiseTo + 1)))
    }
}
