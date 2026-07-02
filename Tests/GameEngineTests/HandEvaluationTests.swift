import XCTest
@testable import GameEngine

final class HandEvaluationTests: XCTestCase {

    // Concise card builder, e.g. c(.ace, .spades).
    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    // MARK: - Category recognition (all ten)

    func testHighCard() {
        let hand = [c(.two, .clubs), c(.five, .diamonds), c(.eight, .spades), c(.jack, .hearts), c(.king, .clubs)]
        XCTAssertEqual(HandEvaluator.evaluate(hand).category, .highCard)
    }

    func testPair() {
        let hand = [c(.nine, .clubs), c(.nine, .diamonds), c(.two, .spades), c(.five, .hearts), c(.king, .clubs)]
        XCTAssertEqual(HandEvaluator.evaluate(hand).category, .pair)
    }

    func testTwoPair() {
        let hand = [c(.nine, .clubs), c(.nine, .diamonds), c(.five, .spades), c(.five, .hearts), c(.king, .clubs)]
        XCTAssertEqual(HandEvaluator.evaluate(hand).category, .twoPair)
    }

    func testThreeOfAKind() {
        let hand = [c(.nine, .clubs), c(.nine, .diamonds), c(.nine, .spades), c(.five, .hearts), c(.king, .clubs)]
        XCTAssertEqual(HandEvaluator.evaluate(hand).category, .threeOfAKind)
    }

    func testStraight() {
        let hand = [c(.five, .clubs), c(.six, .diamonds), c(.seven, .spades), c(.eight, .hearts), c(.nine, .clubs)]
        XCTAssertEqual(HandEvaluator.evaluate(hand).category, .straight)
    }

    func testFlush() {
        let hand = [c(.two, .hearts), c(.five, .hearts), c(.eight, .hearts), c(.jack, .hearts), c(.king, .hearts)]
        XCTAssertEqual(HandEvaluator.evaluate(hand).category, .flush)
    }

    func testFullHouse() {
        let hand = [c(.nine, .clubs), c(.nine, .diamonds), c(.nine, .spades), c(.five, .hearts), c(.five, .clubs)]
        XCTAssertEqual(HandEvaluator.evaluate(hand).category, .fullHouse)
    }

    func testFourOfAKind() {
        let hand = [c(.nine, .clubs), c(.nine, .diamonds), c(.nine, .spades), c(.nine, .hearts), c(.five, .clubs)]
        XCTAssertEqual(HandEvaluator.evaluate(hand).category, .fourOfAKind)
    }

    func testStraightFlush() {
        let hand = [c(.five, .clubs), c(.six, .clubs), c(.seven, .clubs), c(.eight, .clubs), c(.nine, .clubs)]
        XCTAssertEqual(HandEvaluator.evaluate(hand).category, .straightFlush)
    }

    func testRoyalFlush() {
        let hand = [c(.ten, .spades), c(.jack, .spades), c(.queen, .spades), c(.king, .spades), c(.ace, .spades)]
        XCTAssertEqual(HandEvaluator.evaluate(hand).category, .royalFlush)
    }

    // MARK: - Tricky cases

    func testRoyalFlushIsNotConfusedWithPlainStraightFlush() {
        let royal = [c(.ten, .spades), c(.jack, .spades), c(.queen, .spades), c(.king, .spades), c(.ace, .spades)]
        let straightFlush = [c(.nine, .clubs), c(.ten, .clubs), c(.jack, .clubs), c(.queen, .clubs), c(.king, .clubs)]
        XCTAssertEqual(HandEvaluator.evaluate(royal).category, .royalFlush)
        XCTAssertEqual(HandEvaluator.evaluate(straightFlush).category, .straightFlush)
        XCTAssertGreaterThan(HandEvaluator.evaluate(royal), HandEvaluator.evaluate(straightFlush))
    }

    func testWheelIsAStraightNotHighCard() {
        // A-2-3-4-5, the "wheel": the ace plays low.
        let wheel = [c(.ace, .clubs), c(.two, .diamonds), c(.three, .spades), c(.four, .hearts), c(.five, .clubs)]
        let rank = HandEvaluator.evaluate(wheel)
        XCTAssertEqual(rank.category, .straight)
        // Its high card is the five, so it loses to a 2-3-4-5-6 straight.
        let sixHigh = [c(.two, .clubs), c(.three, .diamonds), c(.four, .spades), c(.five, .hearts), c(.six, .clubs)]
        XCTAssertLessThan(rank, HandEvaluator.evaluate(sixHigh))
    }

    func testWheelStraightFlush() {
        let wheel = [c(.ace, .hearts), c(.two, .hearts), c(.three, .hearts), c(.four, .hearts), c(.five, .hearts)]
        let rank = HandEvaluator.evaluate(wheel)
        XCTAssertEqual(rank.category, .straightFlush, "A-2-3-4-5 same suit is a straight flush, not royal.")
    }

    func testAceHighStraightIsNotAWheel() {
        let broadway = [c(.ten, .clubs), c(.jack, .diamonds), c(.queen, .spades), c(.king, .hearts), c(.ace, .clubs)]
        XCTAssertEqual(HandEvaluator.evaluate(broadway).category, .straight)
    }

    // MARK: - Comparisons within a category

    func testPairOfAcesBeatsPairOfKings() {
        let aces = [c(.ace, .clubs), c(.ace, .diamonds), c(.five, .spades), c(.seven, .hearts), c(.nine, .clubs)]
        let kings = [c(.king, .clubs), c(.king, .diamonds), c(.five, .spades), c(.seven, .hearts), c(.nine, .clubs)]
        XCTAssertGreaterThan(HandEvaluator.evaluate(aces), HandEvaluator.evaluate(kings))
    }

    func testKickerDecidesEqualPairs() {
        // Both pair of Aces; the higher side kicker wins.
        let highKicker = [c(.ace, .clubs), c(.ace, .diamonds), c(.king, .spades), c(.seven, .hearts), c(.two, .clubs)]
        let lowKicker  = [c(.ace, .hearts), c(.ace, .spades), c(.queen, .spades), c(.seven, .clubs), c(.two, .diamonds)]
        XCTAssertGreaterThan(HandEvaluator.evaluate(highKicker), HandEvaluator.evaluate(lowKicker))
    }

    func testExactTieIsSplitPot() {
        // Same ranks, different suits ⇒ identical strength ⇒ split pot.
        let a = [c(.ace, .clubs), c(.ace, .diamonds), c(.king, .spades), c(.seven, .hearts), c(.two, .clubs)]
        let b = [c(.ace, .hearts), c(.ace, .spades), c(.king, .hearts), c(.seven, .clubs), c(.two, .diamonds)]
        XCTAssertEqual(HandEvaluator.evaluate(a), HandEvaluator.evaluate(b))
        XCTAssertEqual(HandEvaluator.compare(a, b), .tie)
    }

    func testHigherTwoPairWins() {
        let acesAndKings = [c(.ace, .clubs), c(.ace, .diamonds), c(.king, .spades), c(.king, .hearts), c(.two, .clubs)]
        let queensAndJacks = [c(.queen, .clubs), c(.queen, .diamonds), c(.jack, .spades), c(.jack, .hearts), c(.ace, .clubs)]
        XCTAssertGreaterThan(HandEvaluator.evaluate(acesAndKings), HandEvaluator.evaluate(queensAndJacks))
    }

    func testCompareReportsWinLose() {
        let flush = [c(.two, .hearts), c(.five, .hearts), c(.eight, .hearts), c(.jack, .hearts), c(.king, .hearts)]
        let straight = [c(.five, .clubs), c(.six, .diamonds), c(.seven, .spades), c(.eight, .hearts), c(.nine, .clubs)]
        XCTAssertEqual(HandEvaluator.compare(flush, straight), .win)
        XCTAssertEqual(HandEvaluator.compare(straight, flush), .lose)
    }

    // MARK: - Best-of-seven (Texas Hold'em)

    func testBestFiveOfSevenPicksFlush() {
        // Seven cards containing a five-card heart flush plus noise.
        let seven = [
            c(.two, .hearts), c(.five, .hearts), c(.eight, .hearts), c(.jack, .hearts), c(.king, .hearts),
            c(.ace, .spades), c(.ace, .clubs) // a pair of aces that must be ignored in favour of the flush
        ]
        let rank = HandEvaluator.evaluate(seven)
        XCTAssertEqual(rank.category, .flush)
    }

    func testBestFiveOfSevenFindsStraightAcrossBoard() {
        let seven = [
            c(.five, .clubs), c(.six, .diamonds), c(.seven, .spades), c(.eight, .hearts), c(.nine, .clubs),
            c(.two, .diamonds), c(.king, .hearts)
        ]
        XCTAssertEqual(HandEvaluator.evaluate(seven).category, .straight)
    }

    func testBestFiveOfSevenPrefersFullHouseOverTrips() {
        let seven = [
            c(.nine, .clubs), c(.nine, .diamonds), c(.nine, .spades),
            c(.five, .hearts), c(.five, .clubs),
            c(.two, .diamonds), c(.king, .hearts)
        ]
        XCTAssertEqual(HandEvaluator.evaluate(seven).category, .fullHouse)
    }
}
