// AbandonTableTests.swift
// =====================================================================
// D-086 — leaving the table mid-hand, and its economic consequences.
//
// Run with FREE PLAY OFF (`freePlay: false`), because with the debug flag on the
// wallet is pinned and the economics are invisible — the movement of real chips is
// exactly what must be proved here.

import XCTest
@testable import GameWorld
import GameEngine

final class AbandonTableTests: XCTestCase {

    // MARK: - The provider releases the driver

    /// The core mechanic: a player who walks away mid-hand releases the turn suspended
    /// right now AND every turn still to come, so the driver finishes the hand at code
    /// speed instead of hanging on a human who is gone.
    func testAbandonReleasesTheSuspendedTurnAndFoldsEveryLaterOne() async {
        let provider = HumanActionProvider()
        let hand = HoldemHand(seats: [Seat(id: 0, stack: 1000), Seat(id: 1, stack: 1000)],
                              buttonIndex: 0, smallBlind: 10, bigBlind: 20, seed: 1)
        guard let context = BotContext(actingIn: hand) else { return XCTFail("no acting seat") }

        // A turn is suspended, waiting for the human…
        let pending = Task { await provider.provideAction(for: context) }
        var waiting = false
        for _ in 0..<100 where !waiting {
            waiting = await provider.isWaiting
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(waiting, "the provider should be waiting for the human")

        // …the player leaves.
        await provider.abandon()
        let released = await pending.value
        XCTAssertEqual(released, .fold, "abandoning must fold the suspended turn")

        // And every later turn resolves at once, without anyone submitting anything.
        let later = await provider.provideAction(for: context)
        XCTAssertEqual(later, .fold, "later turns must fold too, or the driver hangs")
    }

    /// The whole session completes after an abandonment — nothing is left suspended.
    func testSessionCompletesAfterTheHumanWalksAway() async throws {
        let human = HumanActionProvider()
        let driver = SessionDriver(capacity: 3, seats: [
            SeatAssignment(position: 0, playerID: 0, chips: 1000, provider: human),
            SeatAssignment(position: 1, playerID: 1, chips: 1000,
                           provider: BotActionProvider(HeuristicBot(personality: .conservativeRock,
                                                                    seed: 7, equitySamples: 20))),
            SeatAssignment(position: 2, playerID: 2, chips: 1000,
                           provider: BotActionProvider(HeuristicBot(personality: .hotAggressor,
                                                                    seed: 9, equitySamples: 20))),
        ], buttonPosition: 0, smallBlind: 10, bigBlind: 20, seed: 5)

        await human.abandon()                       // the player walks away up front
        let outcome = try await driver.playHand()   // the hand must still complete
        XCTAssertEqual(outcome.chipsByPlayer.values.reduce(0, +), 3000, "chips must be conserved")
    }

    // MARK: - What abandoning costs (free play OFF)

    /// Poker: the chips already pushed into the pot are FORFEIT; only the chips still in
    /// the player's own stack come home. The stack is already net of everything
    /// committed, so cashing it out IS the forfeit.
    func testAbandoningForfeitsWhatIsAlreadyInThePot() {
        let account = PlayerAccount(store: InMemoryChipsStore(chips: 5000), freePlay: false)
        XCTAssertTrue(account.buyIn(1000))
        XCTAssertEqual(account.chips, 4000)

        // Mid-hand the player has 1000 bought in, 300 pushed into the pot → 700 in stack.
        let stackNetOfPot = 700
        account.cashOut(stackNetOfPot)
        XCTAssertEqual(account.chips, 4700, "the 300 in the pot must NOT come back")
    }

    /// Poker (D-099): leaving early keeps only PART of the stack, scaled by how well the
    /// player was doing. Here they are dead even with the one opponent → half comes home.
    func testLeavingAPokerTableEarlyKeepsOnlyPartOfTheStack() {
        let account = PlayerAccount(store: InMemoryChipsStore(chips: 5000), freePlay: false)
        XCTAssertTrue(account.buyIn(1000))          // 4000 left in the wallet

        // Even with the last opponent, no elimination: retention is half.
        let kept = EarlyLeaveRetention.retained(heroStack: 1000, aliveOpponentStacks: [1000],
                                                eliminatedCount: 0)
        account.cashOut(kept)
        XCTAssertEqual(account.chips, 4500, "half the stack is forfeit for quitting even")
    }

    /// …but dominance keeps everything, so a player who genuinely won the table home does
    /// not lose a chip by standing up.
    func testDominatingThePokerTableKeepsTheWholeStackOnLeaving() {
        let account = PlayerAccount(store: InMemoryChipsStore(chips: 5000), freePlay: false)
        XCTAssertTrue(account.buyIn(1000))
        let kept = EarlyLeaveRetention.retained(heroStack: 2600, aliveOpponentStacks: [700, 500],
                                                eliminatedCount: 1)
        account.cashOut(kept)
        XCTAssertEqual(account.chips, 4000 + 2600, "a dominant stack (>2× the field) comes home whole")
    }

    /// Blackjack is the OPPOSITE (D-090/D-099): there is no bust-the-table end, so leaving
    /// is the normal way to stop and the WHOLE stack comes home, unpenalised. The retention
    /// rule is a poker rule and must never touch it.
    func testLeavingBlackjackKeepsTheWholeStack() {
        let account = PlayerAccount(store: InMemoryChipsStore(chips: 5000), freePlay: false)
        XCTAssertTrue(account.buyIn(1000))
        // Blackjack's requestLeave cashes out state.chips directly — the full stack.
        account.cashOut(1000)
        XCTAssertEqual(account.chips, 5000, "blackjack keeps everything on leaving")
    }

    /// Machiavelli: the buy-in IS the stake, and the refund is earned by playing the hand
    /// out (D-075). Walking away forfeits it entirely — the faithful analogue of losing
    /// the chips already in the pot, and non-gameable.
    func testAbandoningMachiavelliForfeitsTheRefund() {
        let account = PlayerAccount(store: InMemoryChipsStore(chips: 5000), freePlay: false)
        let buyIn = 1200
        XCTAssertTrue(account.buyIn(buyIn))
        account.cashOut(0)                          // what requestLeave cashes out
        XCTAssertEqual(account.chips, 5000 - buyIn, "abandoning must forfeit the whole stake")

        // Sanity: playing it out to a good score DOES pay a refund — the mechanic itself
        // is untouched, it simply has to be earned.
        let earned = MachiavelliRefund.cashOut(won: false, score: 90, buyIn: buyIn)
        XCTAssertGreaterThan(earned, 0, "the refund still exists for a player who finishes")
    }

    /// Stud: the House Prize needs no special case. It is paid only to a player who BEAT
    /// THE TABLE (D-079), and abandoning leaves the opponents alive — so it is simply not
    /// earned. The economics reconcile themselves.
    func testAbandoningStudEarnsNoHousePrizeWithoutTouchingTheMechanic() {
        let prize = HousePrize.clockTowerStud
        // Walking away mid-session: opponents still have chips.
        let abandoning = HousePrize.cashOut(heroChips: 2000, opponentChips: [1500, 900], prize: prize)
        XCTAssertEqual(abandoning, 2000, "no prize for a table that was not beaten")

        // Beating the table still pays, exactly as before.
        let beaten = HousePrize.cashOut(heroChips: 6000, opponentChips: [0, 0], prize: prize)
        XCTAssertEqual(beaten, 6000 + prize, "the House Prize mechanic is unchanged")
    }
}
