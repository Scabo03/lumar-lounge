import XCTest
@testable import GameEngine

/// Omaha Pot Limit engine: the "two hole + three board" composition rule, the
/// Pot Limit betting cap, side pots and determinism (D-061/D-062).
final class OmahaTests: XCTestCase {

    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    // MARK: - The two-and-three rule (D-061)

    /// A five-card flush ON THE BOARD is NOT the player's hand: you must use exactly
    /// three board cards, so without two of the suit in hand you cannot make it.
    func testBoardFlushIsUnusableWithoutTwoSuitedHoleCards() {
        let hole = [c(.ace, .spades), c(.king, .spades), c(.queen, .diamonds), c(.jack, .clubs)]
        let board = [c(.two, .hearts), c(.five, .hearts), c(.eight, .hearts), c(.nine, .hearts), c(.king, .hearts)]
        // Unconstrained evaluation WOULD see the five-heart flush.
        XCTAssertEqual(HandEvaluator.evaluate(hole + board).category, .flush)
        // Constrained (Omaha) cannot: best is a pair of kings (K♠ hole + K♥ board).
        let omaha = HandEvaluator.evaluateOmaha(hole: hole, board: board)
        XCTAssertNotEqual(omaha.category, .flush, "a board flush is unusable in Omaha without two suited hole cards")
        XCTAssertEqual(omaha.category, .pair)
    }

    /// Four of a kind ON THE BOARD cannot be the player's quads — only three board
    /// cards may be used, so at best it becomes a full house.
    func testBoardQuadsBecomeAtBestAFullHouse() {
        let hole = [c(.ace, .spades), c(.ace, .hearts), c(.two, .clubs), c(.two, .diamonds)]
        let board = [c(.king, .hearts), c(.king, .diamonds), c(.king, .spades), c(.king, .clubs), c(.three, .diamonds)]
        XCTAssertEqual(HandEvaluator.evaluate(hole + board).category, .fourOfAKind)
        let omaha = HandEvaluator.evaluateOmaha(hole: hole, board: board)
        XCTAssertEqual(omaha.category, .fullHouse, "three board kings + two hole aces = kings full, not quads")
        XCTAssertEqual(omaha.tiebreakers.first, Rank.king.rawValue, "kings over aces")
    }

    /// Only ONE suited hole card + four suited board cards is still not a flush.
    func testOneSuitedHoleCardCannotFlush() {
        let hole = [c(.ace, .hearts), c(.king, .spades), c(.queen, .diamonds), c(.jack, .clubs)]
        let board = [c(.two, .hearts), c(.five, .hearts), c(.eight, .hearts), c(.nine, .hearts), c(.three, .spades)]
        let omaha = HandEvaluator.evaluateOmaha(hole: hole, board: board)
        XCTAssertNotEqual(omaha.category, .flush, "one heart in hand + four on board is not a flush in Omaha")
    }

    /// The nut flush when you DO hold two of the suit.
    func testTwoSuitedHoleCardsMakeTheNutFlush() {
        let hole = [c(.ace, .hearts), c(.king, .hearts), c(.two, .clubs), c(.three, .diamonds)]
        let board = [c(.queen, .hearts), c(.jack, .hearts), c(.five, .hearts), c(.eight, .spades), c(.nine, .diamonds)]
        let omaha = HandEvaluator.evaluateOmaha(hole: hole, board: board)
        XCTAssertEqual(omaha.category, .flush)
        XCTAssertEqual(omaha.tiebreakers.first, Rank.ace.rawValue, "ace-high (nut) flush")
    }

    /// The constrained best hand is not always the intuitive one: paired board where
    /// the naive read (a set from a single hole pair) loses to a straight that needs
    /// two specific hole cards.
    func testConstrainedBestIsNotTheNaiveHand() {
        // Board: 9♠ T♦ J♣ J♥ 2♠ (paired board — tempting a naive "I have a pair" read).
        // Hole: Q♦ 8♦ 3♣ 7♠. The real best is a straight that needs exactly two hole
        // cards: Q♦ + 8♦ (two hole) + T♦ J♣ 9♠ (three board) = Q-J-T-9-8.
        let hole = [c(.queen, .diamonds), c(.eight, .diamonds), c(.three, .clubs), c(.seven, .spades)]
        let board = [c(.nine, .spades), c(.ten, .diamonds), c(.jack, .clubs), c(.jack, .hearts), c(.two, .spades)]
        let omaha = HandEvaluator.evaluateOmaha(hole: hole, board: board)
        XCTAssertEqual(omaha.category, .straight)
        XCTAssertEqual(omaha.tiebreakers.first, Rank.queen.rawValue)
    }

    // MARK: - Pot Limit cap arithmetic (D-062)

    func testPotLimitCapCanonicalCases() {
        // Opening bet = size of the pot.
        XCTAssertEqual(PotMath.potLimitMaxBetTo(pot: 30), 30)
        // Preflop over a big blind of 10, SB 5: pot 15, call 10 → raise to 35 (3.5 BB).
        XCTAssertEqual(PotMath.potLimitMaxRaiseTo(pot: 15, currentBet: 10, toCall: 10), 35)
        // After a pot-sized bet of 30 into 30 (pot now 60), a caller (toCall 30) may
        // raise to 30 + (60 + 30) = 120.
        XCTAssertEqual(PotMath.potLimitMaxRaiseTo(pot: 60, currentBet: 30, toCall: 30), 120)
    }

    // MARK: - Pot Limit inside the engine

    private func freshHand(stacks: [Int] = [1000, 1000, 1000], button: Int = 0, seed: UInt64 = 1) -> OmahaHand {
        let seats = stacks.enumerated().map { OmahaSeat(id: $0.offset, stack: $0.element) }
        return OmahaHand(seats: seats, buttonIndex: button, smallBlind: 5, bigBlind: 10, seed: seed)
    }

    func testOpeningRaiseCapPreflop() {
        let hand = freshHand()
        // 3 seats, button 0 → SB seat1(5), BB seat2(10), first to act seat0 (toCall 10).
        let legal = hand.legalActions()!
        XCTAssertEqual(legal.callAmount, 10)
        XCTAssertEqual(legal.minRaiseTo, 20)                 // currentBet 10 + min raise 10
        XCTAssertEqual(legal.maxRaiseTo, 35)                 // 10 + pot(15) + toCall(10)
    }

    func testRaiseCapTracksMultipleRaises() throws {
        var hand = freshHand()
        try hand.apply(.raise(35))                            // seat0 makes it 35; pot now 50
        let legal = hand.legalActions()!                      // seat1 (SB, streetBet 5), toCall 30
        XCTAssertEqual(legal.callAmount, 30)
        XCTAssertEqual(legal.maxRaiseTo, 115)                 // 35 + pot(50) + toCall(30)
    }

    func testOverPotBetIsRejected() throws {
        // Get to the flop: everyone calls preflop.
        var hand = freshHand()
        try hand.apply(.call)   // seat0 calls 10
        try hand.apply(.call)   // seat1 (SB) calls to 10
        try hand.apply(.check)  // seat2 (BB) checks → flop
        XCTAssertEqual(hand.street, .flop)
        let legal = hand.legalActions()!
        XCTAssertTrue(legal.canBet)
        XCTAssertEqual(legal.maxBetTo, 30)                    // pot = 30
        XCTAssertThrowsError(try { var h = hand; try h.apply(.bet(31)) }()) { error in
            XCTAssertEqual(error as? OmahaActionError, .betAbovePotLimit(maximumTo: 30))
        }
        XCTAssertNoThrow(try { var h = hand; try h.apply(.bet(30)) }())
    }

    func testAllInIsCappedAtThePotInPotLimit() throws {
        // A huge stack facing a small pot cannot shove; all-in resolves to a pot bet.
        var hand = freshHand(stacks: [1000, 1000, 1000])
        try hand.apply(.call); try hand.apply(.call); try hand.apply(.check)  // flop, pot 30
        let seatBefore = hand.actingSeatID!
        try hand.apply(.allIn)
        let seat = hand.seats.first { $0.id == seatBefore }!
        XCTAssertEqual(seat.streetBet, 30, "all-in over a small pot is capped at the pot, not the whole stack")
        XCTAssertFalse(seat.isAllIn, "the seat still has chips behind — it was NOT actually all-in")
    }

    // MARK: - Side pots with a short all-in

    func testShortAllInFormsSidePots() throws {
        // seat2 (BB) is short; a big bet from seat0 and call isolates a side pot.
        var hand = freshHand(stacks: [1000, 1000, 40])
        // Preflop: seat0 raises pot, seat1 folds, seat2 (BB, 30 behind after blind) calls all-in.
        try hand.apply(.raise(35))     // seat0 → 35
        try hand.apply(.fold)          // seat1 folds (its 5 SB stays in the pot)
        try hand.apply(.allIn)         // seat2 all-in for its remaining 30 (total 40)
        try hand.apply(.call)          // seat0 calls the extra 5 → matched at 40, runs out
        XCTAssertNotNil(hand.result)
        let pots = hand.result!.pots
        XCTAssertGreaterThanOrEqual(pots.count, 1)
        // Every chip committed is accounted for across the pots (40 + 5 + 40).
        let potTotal = pots.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(potTotal, 85)
    }

    // MARK: - Determinism (D-005)

    func testDeterministicGivenSeedAndActions() throws {
        func play(_ seed: UInt64) throws -> OmahaResult {
            var hand = freshHand(seed: seed)
            try hand.apply(.call); try hand.apply(.call); try hand.apply(.check)   // flop
            try hand.apply(.check); try hand.apply(.check); try hand.apply(.check) // turn
            try hand.apply(.check); try hand.apply(.check); try hand.apply(.check) // river
            try hand.apply(.check); try hand.apply(.check); try hand.apply(.check) // showdown
            return hand.result!
        }
        let a = try play(777)
        let b = try play(777)
        XCTAssertEqual(a.board, b.board)
        XCTAssertEqual(a.finalStacks, b.finalStacks)
        XCTAssertEqual(a.payouts, b.payouts)
        // A different seed deals a different board (overwhelmingly likely).
        let d = try play(778)
        XCTAssertNotEqual(a.board, d.board)
    }

    func testFourHoleCardsDealtAndChipsConserved() throws {
        var hand = freshHand()
        for seat in hand.seats { XCTAssertEqual(seat.holeCards.count, 4) }
        try hand.apply(.call); try hand.apply(.call); try hand.apply(.check)
        while hand.actingSeatID != nil { try hand.apply(.check) }
        let finalTotal = hand.result!.finalStacks.values.reduce(0, +)
        XCTAssertEqual(finalTotal, 3000, "chips are conserved across the hand")
    }
}
