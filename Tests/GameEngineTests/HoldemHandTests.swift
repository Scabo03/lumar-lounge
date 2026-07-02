import XCTest
@testable import GameEngine

final class HoldemHandTests: XCTestCase {

    // MARK: - Helpers

    private func seats(_ stacks: [Int]) -> [Seat] {
        stacks.enumerated().map { Seat(id: $0.offset, stack: $0.element) }
    }

    /// Finds the current SeatState by id.
    private func state(_ hand: HoldemHand, _ id: Int) -> SeatState {
        hand.seats.first { $0.id == id }!
    }

    // MARK: - Blinds

    func testBlindsPostedAndSubtractedFromStacks() {
        // 3 handed, button = seat 0 ⇒ SB = seat 1, BB = seat 2.
        let hand = HoldemHand(seats: seats([1000, 1000, 1000]),
                              buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 1)

        XCTAssertEqual(state(hand, 1).streetBet, 5)
        XCTAssertEqual(state(hand, 1).stack, 995)
        XCTAssertEqual(state(hand, 2).streetBet, 10)
        XCTAssertEqual(state(hand, 2).stack, 990)
        XCTAssertEqual(hand.currentBet, 10)
        // UTG (seat left of BB) acts first: seat 0.
        XCTAssertEqual(hand.actingSeatID, 0)
        // Everyone has two hole cards.
        XCTAssertTrue(hand.seats.allSatisfy { $0.hole?.cards.count == 2 })
    }

    func testHeadsUpButtonIsSmallBlindAndActsFirstPreflop() {
        // Heads-up: button posts the small blind and acts first preflop.
        let hand = HoldemHand(seats: seats([1000, 1000]),
                              buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 1)
        XCTAssertEqual(state(hand, 0).streetBet, 5)  // button = SB
        XCTAssertEqual(state(hand, 1).streetBet, 10) // other = BB
        XCTAssertEqual(hand.actingSeatID, 0)         // button acts first
    }

    // MARK: - Button rotation

    func testButtonRotates() {
        XCTAssertEqual(HoldemHand.nextButtonIndex(after: 0, seatCount: 3), 1)
        XCTAssertEqual(HoldemHand.nextButtonIndex(after: 2, seatCount: 3), 0)
    }

    func testButtonRotationShiftsBlindsOnNextHand() throws {
        // Hand 1: button 0 (SB seat1, BB seat2). Fold to BB.
        var h1 = HoldemHand(seats: seats([1000, 1000, 1000]),
                            buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 7)
        try h1.apply(.fold) // seat 0 (UTG)
        try h1.apply(.fold) // seat 1 (SB)
        XCTAssertTrue(h1.isComplete)
        let stacks1 = h1.result!.finalStacks

        // Hand 2: rotate the button to seat 1 ⇒ SB seat2, BB seat0.
        let nextButton = HoldemHand.nextButtonIndex(after: 0, seatCount: 3)
        let carried = seats([stacks1[0]!, stacks1[1]!, stacks1[2]!])
        let h2 = HoldemHand(seats: carried, buttonIndex: nextButton,
                            smallBlind: 5, bigBlind: 10, seed: 8)
        XCTAssertEqual(state(h2, 2).streetBet, 5)  // new SB
        XCTAssertEqual(state(h2, 0).streetBet, 10) // new BB
        XCTAssertEqual(h2.actingSeatID, 1)         // UTG = seat left of BB
    }

    // MARK: - Minimum raise (No Limit)

    func testRaiseBelowMinimumIsRejected() {
        var hand = HoldemHand(seats: seats([1000, 1000, 1000]),
                              buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 3)
        // currentBet 10, min raise increment 10 ⇒ min raise to 20.
        XCTAssertThrowsError(try hand.apply(.raise(15))) { error in
            XCTAssertEqual(error as? ActionError, .raiseBelowMinimum(minimumTo: 20))
        }
    }

    func testMinimumRaiseGrowsWithLastRaise() throws {
        var hand = HoldemHand(seats: seats([1000, 1000, 1000]),
                              buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 3)
        try hand.apply(.raise(40)) // seat 0: raise to 40 (increment 30)
        XCTAssertEqual(hand.currentBet, 40)
        // Next raise must be at least the last raise (30) on top ⇒ min raise to 70.
        XCTAssertThrowsError(try hand.apply(.raise(60))) { error in
            XCTAssertEqual(error as? ActionError, .raiseBelowMinimum(minimumTo: 70))
        }
        try hand.apply(.raise(70)) // seat 1: legal
        XCTAssertEqual(hand.currentBet, 70)
    }

    func testCannotCheckFacingABet() {
        var hand = HoldemHand(seats: seats([1000, 1000, 1000]),
                              buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 3)
        XCTAssertThrowsError(try hand.apply(.check)) { error in
            XCTAssertEqual(error as? ActionError, .cannotCheckFacingBet)
        }
    }

    // MARK: - Incomplete all-in does not reopen the action

    func testShortAllInDoesNotReopenActionForThoseWhoActed() throws {
        // seat2 has a short stack so its all-in raise is below a full raise.
        var hand = HoldemHand(seats: [Seat(id: 0, stack: 1000),
                                      Seat(id: 1, stack: 1000),
                                      Seat(id: 2, stack: 150)],
                              buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 5)
        // seat0 (UTG) raises to 100 (increment 90, min next raise-to = 190).
        try hand.apply(.raise(100))
        XCTAssertEqual(hand.actingSeatID, 1)
        try hand.apply(.call) // seat1 calls 100
        XCTAssertEqual(hand.actingSeatID, 2)
        // seat2 all-in: 150 total (10 blind + 140). Increment 50 < 90 ⇒ incomplete.
        try hand.apply(.allIn)
        XCTAssertEqual(hand.currentBet, 150)

        // Action is back on seat0, who already acted: it may call but NOT raise.
        XCTAssertEqual(hand.actingSeatID, 0)
        let legal = hand.legalActions()!
        XCTAssertFalse(legal.canRaise)
        XCTAssertThrowsError(try hand.apply(.raise(300))) { error in
            XCTAssertEqual(error as? ActionError, .actionNotReopened)
        }
        // Calling is fine.
        XCTAssertNoThrow(try hand.apply(.call))
    }

    func testFullRaiseReopensActionForThoseWhoActed() throws {
        var hand = HoldemHand(seats: seats([1000, 1000, 1000]),
                              buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 5)
        try hand.apply(.raise(30)) // seat0
        try hand.apply(.call)      // seat1 calls 30
        // seat2 makes a full raise to 60 ⇒ reopens for seat0 and seat1.
        try hand.apply(.raise(60)) // seat2
        XCTAssertEqual(hand.actingSeatID, 0)
        XCTAssertTrue(hand.legalActions()!.canRaise)
    }

    // MARK: - Side pots through a full hand

    func testSidePotsFromUnequalAllInStacks() throws {
        // Button seat0 (=UTG 3-handed). Stacks 50 / 100 / 100.
        var hand = HoldemHand(seats: seats([50, 100, 100]),
                              buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 11)
        try hand.apply(.allIn) // seat0 all-in 50
        try hand.apply(.allIn) // seat1 (SB) all-in 100
        try hand.apply(.allIn) // seat2 (BB) all-in call 100
        XCTAssertTrue(hand.isComplete)

        XCTAssertEqual(hand.result!.pots, [
            Pot(amount: 150, eligibleSeatIDs: [0, 1, 2]),
            Pot(amount: 100, eligibleSeatIDs: [1, 2]),
        ])
        // Chips are conserved.
        let total = hand.result!.finalStacks.values.reduce(0, +)
        XCTAssertEqual(total, 250)
        XCTAssertEqual(hand.result!.payouts.values.reduce(0, +), 250)
    }

    // MARK: - Showdown assignment

    func testHeadsUpShowdownAwardsPotToBestHand() throws {
        var hand = HoldemHand(seats: seats([100, 100]),
                              buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 21)
        try hand.apply(.allIn) // seat0 (button/SB) all-in
        try hand.apply(.allIn) // seat1 all-in call
        XCTAssertTrue(hand.isComplete)
        let result = hand.result!
        XCTAssertTrue(result.wentToShowdown)

        // Independently evaluate the two revealed hands and check the payout.
        let board = result.board
        let h0 = result.shownHands[0]!.cards + board
        let h1 = result.shownHands[1]!.cards + board
        switch HandEvaluator.compare(h0, h1) {
        case .win:
            XCTAssertEqual(result.payouts[0], 200)
            XCTAssertNil(result.payouts[1])
        case .lose:
            XCTAssertEqual(result.payouts[1], 200)
            XCTAssertNil(result.payouts[0])
        case .tie:
            XCTAssertEqual(result.payouts[0], 100)
            XCTAssertEqual(result.payouts[1], 100)
        }
    }

    func testShowdownSplitPotDividesEvenly() throws {
        // Search a small seed range for a heads-up all-in that ties (the board
        // plays for both). Deterministic: seeds are tried in order.
        var tied: HoldemHand?
        for seed in UInt64(0)..<2000 {
            var hand = HoldemHand(seats: seats([100, 100]),
                                  buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: seed)
            try hand.apply(.allIn)
            try hand.apply(.allIn)
            let r = hand.result!
            let h0 = r.shownHands[0]!.cards + r.board
            let h1 = r.shownHands[1]!.cards + r.board
            if HandEvaluator.compare(h0, h1) == .tie { tied = hand; break }
        }
        let hand = try XCTUnwrap(tied, "Expected a tie within the seed range")
        // Even pot of 200 split exactly in half.
        XCTAssertEqual(hand.result!.payouts[0], 100)
        XCTAssertEqual(hand.result!.payouts[1], 100)
    }

    func testOddChipGoesToSeatLeftOfButton() {
        // winnersOrderedFromButton ranks winners by clockwise distance from the
        // seat left of the button, which receives leftover chips first.
        let hand = HoldemHand(seats: seats([1000, 1000, 1000, 1000]),
                              buttonIndex: 1, smallBlind: 5, bigBlind: 10, seed: 1)
        // Button = 1 ⇒ order starts at seat 2, then 3, 0, 1.
        XCTAssertEqual(hand.winnersOrderedFromButton([0, 2, 3]), [2, 3, 0])
        XCTAssertEqual(hand.winnersOrderedFromButton([0, 1]), [0, 1])
    }

    // MARK: - Fold-out (no showdown)

    func testEveryoneFoldsToOneWinner() throws {
        var hand = HoldemHand(seats: seats([1000, 1000, 1000]),
                              buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 2)
        try hand.apply(.fold) // seat0 (UTG)
        try hand.apply(.fold) // seat1 (SB)
        XCTAssertTrue(hand.isComplete)
        let result = hand.result!
        XCTAssertFalse(result.wentToShowdown)
        XCTAssertEqual(result.payouts[2], 15)        // BB wins SB + BB
        XCTAssertEqual(result.finalStacks[2], 1005)  // 990 posted + 15 won
        XCTAssertEqual(result.finalStacks[1], 995)   // lost the small blind
        XCTAssertEqual(result.finalStacks[0], 1000)  // folded before posting
        XCTAssertTrue(result.shownHands.isEmpty)     // no cards revealed
    }

    // MARK: - All-in on the blind (cannot cover)

    func testShortBigBlindGoesAllInForLess() {
        // seat2 (BB) has only 3 chips but the big blind is 10.
        let hand = HoldemHand(seats: [Seat(id: 0, stack: 1000),
                                      Seat(id: 1, stack: 1000),
                                      Seat(id: 2, stack: 3)],
                              buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 4)
        XCTAssertEqual(state(hand, 2).streetBet, 3)
        XCTAssertEqual(state(hand, 2).stack, 0)
        XCTAssertTrue(state(hand, 2).isAllIn)
        // Others still owe the full (nominal) big blind.
        XCTAssertEqual(hand.currentBet, 10)
    }

    func testShortBlindOnlyEligibleForItsShareOfThePot() throws {
        // BB is all-in short for 3; the other two build a bigger pot.
        var hand = HoldemHand(seats: [Seat(id: 0, stack: 1000),
                                      Seat(id: 1, stack: 1000),
                                      Seat(id: 2, stack: 3)],
                              buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 4)
        try hand.apply(.call) // seat0 calls 10
        try hand.apply(.call) // seat1 (SB) calls 10
        // seat2 is all-in short; seats 0 and 1 still have chips, so they play
        // out the remaining streets. Check it down to reach showdown.
        while !hand.isComplete {
            try hand.apply(.check)
        }
        // Main pot capped at seat2's contribution (3 × 3 = 9), rest is a side pot
        // that seat2 cannot win.
        let pots = hand.result!.pots
        XCTAssertEqual(pots.first, Pot(amount: 9, eligibleSeatIDs: [0, 1, 2]))
        XCTAssertEqual(pots.dropFirst().first, Pot(amount: 14, eligibleSeatIDs: [0, 1])) // (10-3)×2
    }

    // MARK: - Determinism

    func testSameSeedAndActionsProduceSameResult() throws {
        func playOut(seed: UInt64) throws -> HoldemHand {
            var hand = HoldemHand(seats: seats([200, 200, 200]),
                                  buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: seed)
            // Fixed script: UTG raises, SB calls, BB calls; then checks down.
            try hand.apply(.raise(30))
            try hand.apply(.call)
            try hand.apply(.call)
            while !hand.isComplete {
                let legal = hand.legalActions()!
                try hand.apply(legal.canCheck ? .check : .call)
            }
            return hand
        }
        let a = try playOut(seed: 99)
        let b = try playOut(seed: 99)
        XCTAssertEqual(a.board, b.board)
        XCTAssertEqual(a.result!.payouts, b.result!.payouts)
        XCTAssertEqual(a.result!.finalStacks, b.result!.finalStacks)
        for id in 0..<3 {
            XCTAssertEqual(state(a, id).hole, state(b, id).hole)
        }
    }

    func testChipsAreConservedAcrossAFullHand() throws {
        var hand = HoldemHand(seats: seats([200, 350, 90, 500]),
                              buttonIndex: 2, smallBlind: 5, bigBlind: 10, seed: 42)
        while !hand.isComplete {
            let legal = hand.legalActions()!
            try hand.apply(legal.canCheck ? .check : .call)
        }
        let total = hand.result!.finalStacks.values.reduce(0, +)
        XCTAssertEqual(total, 200 + 350 + 90 + 500)
    }

    // MARK: - Full street progression

    func testCheckDownReachesRiverWithFiveBoardCards() throws {
        var hand = HoldemHand(seats: seats([1000, 1000]),
                              buttonIndex: 0, smallBlind: 5, bigBlind: 10, seed: 15)
        try hand.apply(.call)  // seat0 (button/SB) completes to 10
        try hand.apply(.check) // seat1 (BB) checks its option
        // Flop, turn, river: check-check on each street.
        while !hand.isComplete {
            try hand.apply(.check)
        }
        XCTAssertEqual(hand.board.count, 5)
        XCTAssertTrue(hand.result!.wentToShowdown)
    }
}
