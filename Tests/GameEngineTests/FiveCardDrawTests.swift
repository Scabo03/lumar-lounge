import XCTest
@testable import GameEngine

/// Tests for the Five-Card Draw ("Jacks or Better") engine. Independent of the
/// Texas engine; drives deals with explicit actions and, where an exact holding
/// is needed, searches the deterministic seed space (as the Hold'em split test
/// does) rather than trying to stack a shuffled deck.
final class FiveCardDrawTests: XCTestCase {

    // MARK: - Helpers

    private func seats(_ stacks: [Int]) -> [DrawSeat] {
        stacks.enumerated().map { DrawSeat(id: $0.offset, stack: $0.element) }
    }

    private func state(_ hand: FiveCardDrawHand, _ id: Int) -> DrawSeatState {
        hand.seats.first { $0.id == id }!
    }

    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    /// Standard four-handed deal: ante 10, small bet 20, big bet 40, button 0.
    private func deal(seed: UInt64, stacks: [Int] = [1000, 1000, 1000, 1000],
                      button: Int = 0, carry: Int = 0) -> FiveCardDrawHand {
        FiveCardDrawHand(seats: seats(stacks), buttonIndex: button,
                         ante: 10, smallBet: 20, bigBet: 40, seed: seed, carryPot: carry)
    }

    /// A seed whose first-to-act seat does (or does not) hold jacks-or-better.
    private func seedWhereOpener(qualifies: Bool, carry: Int = 0) -> FiveCardDrawHand {
        for seed in UInt64(0)..<10_000 {
            let h = deal(seed: seed, carry: carry)
            let opener = h.actingSeatID!
            if FiveCardDrawHand.qualifies(state(h, opener).cards) == qualifies { return h }
        }
        fatalError("no seed found for qualifies=\(qualifies)")
    }

    /// A seed where nobody can open (no seat holds jacks-or-better).
    private func seedWhereNobodyOpens(carry: Int = 0) -> FiveCardDrawHand {
        for seed in UInt64(0)..<10_000 {
            let h = deal(seed: seed, carry: carry)
            if h.seatsQualifiedToOpen().isEmpty { return h }
        }
        fatalError("no all-weak seed found")
    }

    /// Opens with the first actor, calls around, everyone stands pat, checks the
    /// second round down to showdown.
    private func driveToShowdownStandingPat(_ hand: inout FiveCardDrawHand) throws {
        while hand.phase == .firstBet {
            let legal = hand.legalActions()!
            try hand.apply(legal.canBet ? .bet : .call)
        }
        while hand.phase == .draw {
            try hand.discard([])            // stand pat
        }
        while hand.phase == .secondBet {
            let legal = hand.legalActions()!
            try hand.apply(legal.canCheck ? .check : .call)
        }
    }

    // MARK: - Dealing & ante

    func testInitialDealAntesAndDeck() {
        let hand = deal(seed: 1)
        // Four seats, five cards each, all twenty distinct, deck reduced by 20.
        XCTAssertTrue(hand.seats.allSatisfy { $0.cards.count == 5 })
        XCTAssertEqual(Set(hand.seats.flatMap { $0.cards }).count, 20)
        XCTAssertEqual(hand.cardsRemaining, 52 - 20)
        // Every seat posted the ante; pot is four antes.
        XCTAssertTrue(hand.seats.allSatisfy { $0.stack == 990 })
        XCTAssertEqual(hand.pot, 40)
        // First to act is the seat left of the button.
        XCTAssertEqual(hand.actingSeatID, 1)
        XCTAssertEqual(hand.phase, .firstBet)
    }

    // MARK: - Jacks-or-better detection

    func testQualifiesToOpenIdentifiesJacksOrBetter() {
        // Below the line.
        XCTAssertFalse(FiveCardDrawHand.qualifies([c(.ten, .spades), c(.ten, .hearts),
                                                   c(.three, .diamonds), c(.seven, .clubs), c(.nine, .spades)]))
        XCTAssertFalse(FiveCardDrawHand.qualifies([c(.ace, .spades), c(.king, .hearts),
                                                   c(.three, .diamonds), c(.seven, .clubs), c(.nine, .spades)]))
        // A pair of jacks and better pairs.
        XCTAssertTrue(FiveCardDrawHand.qualifies([c(.jack, .spades), c(.jack, .hearts),
                                                  c(.three, .diamonds), c(.seven, .clubs), c(.nine, .spades)]))
        XCTAssertTrue(FiveCardDrawHand.qualifies([c(.ace, .spades), c(.ace, .hearts),
                                                  c(.three, .diamonds), c(.seven, .clubs), c(.nine, .spades)]))
        // Higher combinations qualify even without a jacks pair.
        XCTAssertTrue(FiveCardDrawHand.qualifies([c(.ten, .spades), c(.ten, .hearts),
                                                  c(.nine, .diamonds), c(.nine, .clubs), c(.two, .spades)])) // two pair
        XCTAssertTrue(FiveCardDrawHand.qualifies([c(.five, .spades), c(.five, .hearts),
                                                  c(.five, .diamonds), c(.king, .clubs), c(.two, .spades)])) // trips
        XCTAssertTrue(FiveCardDrawHand.qualifies([c(.two, .hearts), c(.five, .hearts),
                                                  c(.eight, .hearts), c(.jack, .hearts), c(.king, .hearts)])) // flush
    }

    func testSeatsQualifiedToOpenMatchesPerSeat() {
        let hand = deal(seed: 3)
        for seat in hand.seats {
            XCTAssertEqual(hand.seatsQualifiedToOpen().contains(seat.id),
                           FiveCardDrawHand.qualifies(seat.cards),
                           "seat \(seat.id) qualification mismatch")
        }
    }

    func testOpenerProofReturnsTheQualifyingPair() {
        let proof = FiveCardDrawHand.openerProof([c(.queen, .spades), c(.queen, .hearts),
                                                  c(.three, .diamonds), c(.seven, .clubs), c(.nine, .spades)])
        XCTAssertEqual(Set(proof ?? []), [c(.queen, .spades), c(.queen, .hearts)])
        XCTAssertNil(FiveCardDrawHand.openerProof([c(.ace, .spades), c(.king, .hearts),
                                                   c(.three, .diamonds), c(.seven, .clubs), c(.nine, .spades)]))
    }

    // MARK: - Pass-and-out (progressive pot)

    func testNobodyOpensPassesInAndKeepsAntes() throws {
        var hand = seedWhereNobodyOpens()
        XCTAssertTrue(hand.seatsQualifiedToOpen().isEmpty)
        // Everyone declines to open (checks around).
        while hand.phase == .firstBet { try hand.apply(.check) }
        XCTAssertTrue(hand.isComplete)
        XCTAssertEqual(hand.result!.outcome, .passedIn)
        XCTAssertFalse(hand.result!.wentToShowdown)
        XCTAssertEqual(hand.result!.carriedPot, 40)   // four antes carry forward
        XCTAssertTrue(hand.result!.payouts.isEmpty)
    }

    func testProgressivePotAccumulatesAcrossPassedDeals() throws {
        // Two consecutive passed deals: the antes stack up in the carried pot.
        var carry = 0
        for _ in 0..<2 {
            var hand = seedWhereNobodyOpens(carry: carry)
            while hand.phase == .firstBet { try hand.apply(.check) }
            XCTAssertEqual(hand.result!.outcome, .passedIn)
            carry = hand.result!.carriedPot
        }
        XCTAssertEqual(carry, 80)   // 40 + 40

        // A third, played deal starts with that carried pot and pays it all out.
        var played = seedWhereOpener(qualifies: true, carry: carry)
        XCTAssertEqual(played.pot, carry + 40)   // starts as carry + four fresh antes
        try driveToShowdownStandingPat(&played)
        XCTAssertTrue(played.result!.wentToShowdown)
        // The whole final pot — antes, the round-one betting AND the carried pot —
        // is paid out; nothing is left carried.
        XCTAssertGreaterThan(played.pot, carry + 40)   // betting added to it
        XCTAssertEqual(played.result!.payouts.values.reduce(0, +), played.pot)
        XCTAssertEqual(played.result!.carriedPot, 0)
    }

    // MARK: - Opening and limit betting

    func testFirstBetIsSmallBetAndSecondBetIsBigBet() throws {
        var hand = seedWhereOpener(qualifies: true)
        try hand.apply(.bet)                                  // opener opens
        XCTAssertEqual(hand.legalActions()!.betUnit, 20)      // small bet round 1
        XCTAssertEqual(hand.currentBet, 20)
        while hand.phase == .firstBet {                        // finish round 1
            try hand.apply(.call)
        }
        while hand.phase == .draw { try hand.discard([]) }     // stand pat
        XCTAssertEqual(hand.phase, .secondBet)
        XCTAssertEqual(hand.legalActions()!.betUnit, 40)      // big bet round 2
    }

    func testRaiseCapIsBetPlusThreeRaises() throws {
        var hand = deal(seed: 7)   // opener honour-opens regardless of holding
        try hand.apply(.bet)       // seat1 opens        (escalation 1) -> 20
        XCTAssertEqual(hand.currentBet, 20)
        try hand.apply(.raise)     // seat2 raise        (2)            -> 40
        XCTAssertEqual(hand.currentBet, 40)
        try hand.apply(.raise)     // seat3 re-raise     (3)            -> 60
        try hand.apply(.raise)     // seat0 cap          (4)            -> 80
        XCTAssertEqual(hand.currentBet, 80)
        // Back to the opener, now capped: it may only call or fold.
        let legal = hand.legalActions()!
        XCTAssertEqual(legal.seatID, 1)
        XCTAssertFalse(legal.canRaise)
        XCTAssertEqual(legal.raisesRemaining, 0)
        XCTAssertThrowsError(try hand.apply(.raise)) {
            XCTAssertEqual($0 as? DrawActionError, .raiseCapReached)
        }
        XCTAssertNoThrow(try hand.apply(.call))
    }

    // MARK: - The draw

    func testDrawReplacesDiscardedCards() throws {
        var hand = deal(seed: 9)
        // Open and call round 1 into the draw.
        while hand.phase == .firstBet {
            let legal = hand.legalActions()!
            try hand.apply(legal.canBet ? .bet : .call)
        }
        XCTAssertEqual(hand.phase, .draw)

        let drawer = hand.drawingSeatID!
        let before = state(hand, drawer).cards
        let discards = Array(before.suffix(3))               // throw the low three
        let deckBefore = hand.cardsRemaining
        try hand.discard(discards)

        let after = state(hand, drawer).cards
        XCTAssertEqual(after.count, 5)                        // still exactly five
        XCTAssertEqual(state(hand, drawer).discardCount, 3)
        XCTAssertTrue(state(hand, drawer).hasDrawn)
        XCTAssertEqual(hand.cardsRemaining, deckBefore - 3)   // three drawn from the deck
        // The discarded cards are gone; the two kept cards remain.
        for card in discards { XCTAssertFalse(after.contains(card)) }
        for card in before.prefix(2) { XCTAssertTrue(after.contains(card)) }
        // Sorted, descending by rank.
        XCTAssertEqual(after, FiveCardDrawHand.sorted(after))
    }

    func testDrawKeepsAllCardsInPlayDistinct() throws {
        var hand = deal(seed: 12)
        while hand.phase == .firstBet {
            let legal = hand.legalActions()!
            try hand.apply(legal.canBet ? .bet : .call)
        }
        while hand.phase == .draw {
            let opts = hand.drawOptions()!
            try hand.discard(Array(opts.cards.suffix(2)))    // everyone draws two
        }
        let inPlay = hand.seats.flatMap { $0.cards }
        XCTAssertEqual(Set(inPlay).count, inPlay.count, "cards in play must stay distinct")
    }

    // MARK: - Showdown & winner

    func testShowdownAwardsPotToBestHand() throws {
        var hand = seedWhereOpener(qualifies: true)
        try driveToShowdownStandingPat(&hand)
        let result = hand.result!
        XCTAssertTrue(result.wentToShowdown)
        XCTAssertFalse(result.openerDisqualified)

        // Independently determine the best revealed hand and confirm the payout.
        let best = result.bestHands.max { $0.value < $1.value }!.value
        let winners = result.bestHands.filter { $0.value == best }.map(\.key)
        for id in result.bestHands.keys {
            if winners.contains(id) {
                XCTAssertNotNil(result.payouts[id], "winner \(id) should be paid")
            } else {
                XCTAssertNil(result.payouts[id], "loser \(id) should not be paid")
            }
        }
        XCTAssertEqual(result.payouts.values.reduce(0, +), hand.pot)
    }

    // MARK: - Openers to prove

    func testLegitimateOpenerIsNotDisqualified() throws {
        var hand = seedWhereOpener(qualifies: true)
        let opener = hand.actingSeatID!
        try driveToShowdownStandingPat(&hand)
        let result = hand.result!
        XCTAssertEqual(result.openerSeatID, opener)
        XCTAssertFalse(result.openerDisqualified)
        XCTAssertNotNil(state(hand, opener).openers)   // proof was recorded
    }

    func testBluffOpenerWithoutJacksIsDisqualifiedAtShowdown() throws {
        // The first actor has NO openers, yet honour-opens anyway (a bluff open).
        var hand = seedWhereOpener(qualifies: false)
        let opener = hand.actingSeatID!
        XCTAssertFalse(FiveCardDrawHand.qualifies(state(hand, opener).cards))
        try driveToShowdownStandingPat(&hand)   // callers keep it honest to showdown
        let result = hand.result!
        XCTAssertTrue(result.wentToShowdown)
        XCTAssertEqual(result.openerSeatID, opener)
        XCTAssertTrue(result.openerDisqualified)
        // Auto-loss regardless of its final hand: it wins nothing.
        XCTAssertNil(result.payouts[opener])
        // The whole pot still goes to the other seats.
        XCTAssertEqual(result.payouts.values.reduce(0, +), hand.pot)
        XCTAssertNil(state(hand, opener).openers)
    }

    func testBluffOpenerWinsUncontestedWhenEveryoneFolds() throws {
        // Same weak opener, but this time everyone folds to it: a successful
        // steal is NOT punished (no showdown, no proof required, D-039).
        var hand = seedWhereOpener(qualifies: false)
        let opener = hand.actingSeatID!
        try hand.apply(.bet)                    // bluff-open
        while hand.phase == .firstBet {         // everyone else folds
            try hand.apply(.fold)
        }
        XCTAssertTrue(hand.isComplete)
        let result = hand.result!
        XCTAssertEqual(result.outcome, .foldOut)
        XCTAssertFalse(result.openerDisqualified)
        XCTAssertEqual(result.payouts[opener], hand.pot)
    }

    // MARK: - Determinism

    func testSameSeedAndActionsProduceSameResult() throws {
        func playOut(seed: UInt64) throws -> FiveCardDrawHand {
            var hand = deal(seed: seed)
            try driveToShowdownStandingPat(&hand)
            return hand
        }
        let a = try playOut(seed: 55)
        let b = try playOut(seed: 55)
        XCTAssertEqual(a.result!.payouts, b.result!.payouts)
        XCTAssertEqual(a.result!.finalStacks, b.result!.finalStacks)
        for id in 0..<4 {
            XCTAssertEqual(state(a, id).cards, state(b, id).cards)
        }
    }

    func testChipsAreConservedThroughAPlayedDeal() throws {
        var hand = deal(seed: 31, stacks: [200, 350, 90, 500])
        try driveToShowdownStandingPat(&hand)
        let total = hand.result!.finalStacks.values.reduce(0, +)
        XCTAssertEqual(total, 200 + 350 + 90 + 500)
    }

    // MARK: - Illegal actions rejected

    func testIllegalBettingActionsAreRejected() throws {
        var hand = deal(seed: 2)
        // Nothing to call / nothing to raise at the very start.
        XCTAssertThrowsError(try hand.apply(.call)) {
            XCTAssertEqual($0 as? DrawActionError, .cannotCallNothingToCall)
        }
        XCTAssertThrowsError(try hand.apply(.raise)) {
            XCTAssertEqual($0 as? DrawActionError, .cannotRaiseNothingToRaise)
        }
        try hand.apply(.bet)   // seat1 opens; seat2 now faces a bet
        XCTAssertThrowsError(try hand.apply(.check)) {
            XCTAssertEqual($0 as? DrawActionError, .cannotCheckFacingBet)
        }
        XCTAssertThrowsError(try hand.apply(.bet)) {
            XCTAssertEqual($0 as? DrawActionError, .cannotBetFacingBet)
        }
        // A draw request while betting is illegal.
        XCTAssertThrowsError(try hand.discard([])) {
            XCTAssertEqual($0 as? DrawExchangeError, .notInDrawPhase)
        }
    }

    func testIllegalDrawRequestsAreRejected() throws {
        var hand = deal(seed: 4)
        while hand.phase == .firstBet {
            let legal = hand.legalActions()!
            try hand.apply(legal.canBet ? .bet : .call)
        }
        XCTAssertEqual(hand.phase, .draw)
        // A betting action during the draw is illegal.
        XCTAssertThrowsError(try hand.apply(.check)) {
            XCTAssertEqual($0 as? DrawActionError, .notInBettingPhase)
        }
        // More than four discards, or a card not held.
        let held = hand.drawOptions()!.cards
        XCTAssertThrowsError(try hand.discard(held)) {   // five cards
            XCTAssertEqual($0 as? DrawExchangeError, .tooManyDiscards)
        }
        let notHeld = Card(.ace, .spades)
        if !held.contains(notHeld) {
            XCTAssertThrowsError(try hand.discard([notHeld])) {
                XCTAssertEqual($0 as? DrawExchangeError, .cardNotHeld(notHeld))
            }
        }
    }

    func testActionsAfterCompletionAreRejected() throws {
        var hand = seedWhereOpener(qualifies: true)
        try driveToShowdownStandingPat(&hand)
        XCTAssertTrue(hand.isComplete)
        XCTAssertThrowsError(try hand.apply(.check)) {
            XCTAssertEqual($0 as? DrawActionError, .handComplete)
        }
    }

    // MARK: - Odd chip ordering

    func testOddChipGoesToSeatLeftOfButton() {
        let hand = deal(seed: 1, button: 1)
        // Button 1 ⇒ order starts at seat 2, then 3, 0, 1.
        XCTAssertEqual(hand.winnersOrderedFromButton([0, 2, 3]), [2, 3, 0])
        XCTAssertEqual(hand.winnersOrderedFromButton([0, 1]), [0, 1])
    }
}
