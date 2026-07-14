// StudHand.swift
// =====================================================================
// The Seven-Card Stud Pot Limit hand engine: a deterministic, turn-based state machine
// that plays a single hand from the ante to the award of the pot(s) at showdown (or to
// the last seat standing).
//
// It is a value type (`struct`) with `mutating` transitions — cheap to snapshot,
// impossible to alias, trivially reproducible. Given the same `seed` and the same
// sequence of actions it always produces the same result (D-005 style).
//
// CANONICAL RULES fixed here (D-077) so a future session need not rediscover them:
//
//   • Deck: one standard 52-card deck. Best FIVE of the SEVEN cards each player holds
//     wins (unconstrained — `HandEvaluator.evaluate`, unlike Omaha's 2+3).
//   • Ante: every seat antes `ante` before the deal.
//   • Dealing / streets (FIVE betting rounds):
//       – Third street: 2 DOWN + 1 UP each. Round 1.
//       – Fourth / fifth / sixth: 1 UP each. Rounds 2–4.
//       – Seventh street ("the river"): 1 DOWN each. Round 5.
//     So an active player ends with 3 down + 4 up = 7 cards.
//   • Who opens each round:
//       – Third: the LOWEST up card must post the BRING-IN (a forced partial bet). Ties
//         broken by suit, clubs lowest (bring-in suit order clubs<diamonds<hearts<spades).
//       – Fourth–seventh: the HIGHEST poker hand SHOWING in the up cards acts first.
//   • Betting: POT LIMIT — every bet/raise capped at the size of the pot
//     (`PotMath.potLimitMax…`). A single minimum-bet size `bet` (the small/big-bet split
//     of fixed-limit Stud is dropped: in Pot Limit the pot cap governs sizing). The
//     bring-in is smaller than `bet`; a player "completes" it by raising to `bet`.
//     No cap on the number of raises — Pot Limit self-limits (as in Omaha).
//   • Deck exhaustion: with many players the 52-card deck can run out on seventh street
//     (7×8 = 56 > 52). Canonically, when there aren't enough cards to deal everyone a
//     seventh card, ONE shared COMMUNITY card is dealt face up and used by all remaining
//     players as their seventh (`communityCard`). With the ClockTower's 3 players this
//     never triggers, but the engine handles and tests it.
//
// Foundation only.

import Foundation

/// A single hand of Seven-Card Stud Pot Limit in progress.
public struct StudHand {

    // MARK: Configuration (immutable for the hand)

    public let ante: Int
    /// The forced partial opening bet posted by the low up card on third street.
    public let bringIn: Int
    /// The minimum full bet size (the "completion" amount and the base raise increment).
    public let bet: Int

    // MARK: Observable state

    public private(set) var seats: [StudSeatState]
    public private(set) var street: StudStreet
    /// Highest street bet any seat has made this street (the amount to match).
    public private(set) var currentBet: Int
    /// Index of the seat to act, or `nil` once the hand is complete.
    public private(set) var actingIndex: Int?
    /// The outcome, once the hand has ended.
    public private(set) var result: StudResult?
    /// The shared community card, if the deck was exhausted on seventh street. Public so
    /// a narrator can announce it; `nil` in the normal case.
    public private(set) var communityCard: Card?

    // MARK: Internal state

    private var deck: Deck
    /// Size of the last full bet/raise this street — the minimum legal raise increment.
    private var lastRaiseSize: Int
    /// Whether the current bet level was set by a *full* bet/raise. A short all-in leaves
    /// this `false`, which stops seats that have already acted from re-raising.
    private var actionReopened: Bool
    /// Whether the bring-in has been COMPLETED to a full bet this hand. While `false`
    /// (third street, only the bring-in posted) the minimum raise is the completion.
    private var betComplete: Bool

    // MARK: - Init

    /// Sets up a hand: seats the players, takes the antes, deals third street (2 down +
    /// 1 up each), posts the bring-in for the low up card, and hands the turn to the
    /// first voluntary actor.
    ///
    /// - Parameters:
    ///   - seats: 2–8 seats in clockwise order; each needs a positive stack and a unique
    ///     id (worst case 8×7 = 56 cards, handled via the community-card exhaustion rule).
    ///   - ante/bringIn/bet: positive, with `bringIn <= bet`.
    ///   - seed: seed for the deterministic shuffle.
    public init(seats seatConfigs: [StudSeat], ante: Int, bringIn: Int, bet: Int, seed: UInt64) {
        precondition((2...8).contains(seatConfigs.count), "Stud requires 2–8 seats.")
        precondition(ante >= 0 && bringIn > 0 && bet > 0 && bringIn <= bet, "Invalid ante/bring-in/bet.")
        precondition(seatConfigs.allSatisfy { $0.stack > 0 }, "Every seat must have a positive stack.")
        precondition(Set(seatConfigs.map(\.id)).count == seatConfigs.count, "Seat ids must be unique.")

        self.ante = ante
        self.bringIn = bringIn
        self.bet = bet
        self.seats = seatConfigs.map {
            StudSeatState(id: $0.id, stack: $0.stack, holeCards: [], upCards: [], streetBet: 0,
                          totalBet: 0, hasFolded: false, isAllIn: false, hasActed: false)
        }
        self.street = .third
        self.currentBet = 0
        self.actingIndex = nil
        self.result = nil
        self.communityCard = nil
        self.lastRaiseSize = bet
        self.actionReopened = true
        self.betComplete = false
        var deck = Deck()
        deck.shuffle(seed: seed)
        self.deck = deck

        postAntes()
        dealThirdStreet()
        beginThirdStreet()
    }

    // MARK: - Positions

    private var seatCount: Int { seats.count }
    private func seatAfter(_ index: Int) -> Int { (index + 1) % seatCount }

    /// Every chip already in the middle across all streets (the current pot) — the basis
    /// of the Pot Limit cap. A seat's own street bet and its ante are already counted here.
    private var potTotal: Int { seats.reduce(0) { $0 + $1.totalBet } }

    // MARK: - Setup steps

    private mutating func postAntes() {
        guard ante > 0 else { return }
        for i in seats.indices {
            let posted = min(ante, seats[i].stack)
            seats[i].stack -= posted
            seats[i].totalBet += posted
            if seats[i].stack == 0 { seats[i].isAllIn = true }
        }
    }

    /// Deals third street: two DOWN cards then one UP card to each seat, one at a time in
    /// seat order. The order is fixed (hence reproducible); it doesn't affect fairness
    /// since the deck is already randomly shuffled.
    private mutating func dealThirdStreet() {
        for _ in 0..<2 {
            for i in seats.indices { seats[i].holeCards.append(deck.draw()!) }
        }
        for i in seats.indices { seats[i].upCards.append(deck.draw()!) }
    }

    /// Posts the forced bring-in and opens third-street betting. If no one but the
    /// bring-in seat can act (everyone else all-in from antes), the hand runs out.
    private mutating func beginThirdStreet() {
        guard let bringInIndex = bringInSeatIndex() else {
            // Nobody can post a bring-in (all all-in from antes) — deal to showdown.
            runOutAndFinish(); return
        }
        let posted = min(bringIn, seats[bringInIndex].stack)
        seats[bringInIndex].stack -= posted
        seats[bringInIndex].streetBet = posted
        seats[bringInIndex].totalBet += posted
        if seats[bringInIndex].stack == 0 { seats[bringInIndex].isAllIn = true }
        currentBet = posted
        lastRaiseSize = bet
        actionReopened = true
        betComplete = false   // the bring-in is a partial bet awaiting completion

        if activePlayerCount >= 2, let first = firstToAct(from: seatAfter(bringInIndex)) {
            actingIndex = first
        } else {
            runOutAndFinish()
        }
    }

    /// The seat that must bring in on third street: the LOWEST up card by rank, ties by
    /// suit (clubs lowest), among seats that can still act (not all-in from the ante).
    private func bringInSeatIndex() -> Int? {
        var bestIndex: Int?
        for i in seats.indices where seats[i].canAct {
            guard let up = seats[i].upCards.first else { continue }
            if bestIndex == nil || isLowerForBringIn(up, than: seats[bestIndex!].upCards.first!) {
                bestIndex = i
            }
        }
        return bestIndex
    }

    /// Bring-in ordering: lower rank first, ties broken by suit with CLUBS lowest.
    private func isLowerForBringIn(_ a: Card, than b: Card) -> Bool {
        if a.rank.rawValue != b.rank.rawValue { return a.rank.rawValue < b.rank.rawValue }
        return StudShowing.bringInSuitOrder(a.suit) < StudShowing.bringInSuitOrder(b.suit)
    }

    // MARK: - Public queries

    /// The id of the seat to act, if any.
    public var actingSeatID: Int? {
        guard let actingIndex else { return nil }
        return seats[actingIndex].id
    }

    public var isComplete: Bool { result != nil }

    /// The legal actions for the seat currently on turn, or `nil` if the hand is
    /// complete. Bet/raise maxima already fold in the Pot Limit ceiling and the stack.
    public func legalActions() -> StudLegalActions? {
        guard let index = actingIndex else { return nil }
        let seat = seats[index]
        let toCall = max(0, currentBet - seat.streetBet)
        let stackCapTo = seat.streetBet + seat.stack

        let canCheck = toCall == 0
        let canCall = toCall > 0
        let canBet = currentBet == 0 && seat.stack > 0
        let canReopen = !seat.hasActed || actionReopened

        let potBetTo = PotMath.potLimitMaxBetTo(pot: potTotal)
        let maxBetTo = min(potBetTo, stackCapTo)
        let potRaiseTo = PotMath.potLimitMaxRaiseTo(pot: potTotal, currentBet: currentBet, toCall: toCall)
        let maxRaiseTo = min(potRaiseTo, stackCapTo)

        // Before the bring-in is completed the minimum raise is the completion (the full
        // bet); afterwards it is the usual currentBet + lastRaiseSize.
        let rawMinRaiseTo = betComplete ? currentBet + lastRaiseSize : bet
        let canRaise = currentBet > 0 && maxRaiseTo > currentBet && canReopen

        return StudLegalActions(
            seatID: seat.id,
            canFold: true,
            canCheck: canCheck,
            canCall: canCall,
            callAmount: min(toCall, seat.stack),
            canBet: canBet,
            minBetTo: min(bet, maxBetTo),
            maxBetTo: maxBetTo,
            canRaise: canRaise,
            minRaiseTo: min(rawMinRaiseTo, maxRaiseTo),
            maxRaiseTo: maxRaiseTo,
            canAllIn: seat.stack > 0)
    }

    // MARK: - Applying actions

    /// Applies `action` for the seat on turn and advances the hand.
    /// - Throws: `StudActionError` if the action is illegal in the current state.
    public mutating func apply(_ action: StudAction) throws {
        guard result == nil, let index = actingIndex else { throw StudActionError.handComplete }

        switch action {
        case .fold:          applyFold(index)
        case .check:         try applyCheck(index)
        case .call:          applyCall(index)
        case .bet(let to):   try applyBet(index, to: to)
        case .raise(let to): try applyRaise(index, to: to)
        case .allIn:         applyAllIn(index)
        }

        settle()
    }

    private mutating func applyFold(_ index: Int) {
        seats[index].hasFolded = true
        seats[index].hasActed = true
    }

    private mutating func applyCheck(_ index: Int) throws {
        guard amountToCall(index) == 0 else { throw StudActionError.cannotCheckFacingBet }
        seats[index].hasActed = true
    }

    private mutating func applyCall(_ index: Int) {
        let toCall = amountToCall(index)
        let pay = min(toCall, seats[index].stack)
        placeChips(index, toStreetBet: seats[index].streetBet + pay)
    }

    private mutating func applyBet(_ index: Int, to: Int) throws {
        guard currentBet == 0 else { throw StudActionError.cannotBetFacingBet }
        guard to > 0 else { throw StudActionError.nonPositiveAmount }
        let stackCapTo = seats[index].streetBet + seats[index].stack
        guard to <= stackCapTo else { throw StudActionError.amountExceedsStack(maximumTo: stackCapTo) }
        let potCapTo = PotMath.potLimitMaxBetTo(pot: potTotal)
        guard to <= potCapTo else { throw StudActionError.betAbovePotLimit(maximumTo: min(potCapTo, stackCapTo)) }
        let isAllInBet = to == stackCapTo
        guard to >= bet || isAllInBet else { throw StudActionError.betBelowMinimum(minimum: bet) }
        commitAggressive(index, toStreetBet: to)
    }

    private mutating func applyRaise(_ index: Int, to: Int) throws {
        guard currentBet > 0 else { throw StudActionError.cannotRaiseNothingToRaise }
        guard to > currentBet else { throw StudActionError.raiseBelowMinimum(minimumTo: minRaiseToNow()) }
        let stackCapTo = seats[index].streetBet + seats[index].stack
        guard to <= stackCapTo else { throw StudActionError.amountExceedsStack(maximumTo: stackCapTo) }
        let toCall = amountToCall(index)
        let potCapTo = PotMath.potLimitMaxRaiseTo(pot: potTotal, currentBet: currentBet, toCall: toCall)
        guard to <= potCapTo else { throw StudActionError.raiseAbovePotLimit(maximumTo: min(potCapTo, stackCapTo)) }
        guard !seats[index].hasActed || actionReopened else { throw StudActionError.actionNotReopened }
        let isAllInRaise = to == stackCapTo
        guard to >= minRaiseToNow() || isAllInRaise else {
            throw StudActionError.raiseBelowMinimum(minimumTo: minRaiseToNow())
        }
        commitAggressive(index, toStreetBet: to)
    }

    /// The minimum legal raise "to" right now (completion, or currentBet + lastRaiseSize).
    private func minRaiseToNow() -> Int { betComplete ? currentBet + lastRaiseSize : bet }

    /// "Commit as much as the rules allow." Under Pot Limit this is the whole stack when
    /// it fits under the pot ceiling, otherwise a pot-sized bet/raise; when the stack
    /// cannot even cover the call it is an all-in call for less. Always legal — the
    /// driver's safe fallback, so it never throws.
    private mutating func applyAllIn(_ index: Int) {
        let stackCapTo = seats[index].streetBet + seats[index].stack
        if currentBet == 0 {
            let to = min(stackCapTo, PotMath.potLimitMaxBetTo(pot: potTotal))
            commitAggressive(index, toStreetBet: to)
        } else if stackCapTo <= currentBet {
            placeChips(index, toStreetBet: stackCapTo)          // all-in call for less
        } else if seats[index].hasActed && !actionReopened {
            placeChips(index, toStreetBet: min(stackCapTo, currentBet))
        } else {
            let toCall = amountToCall(index)
            let potCapTo = PotMath.potLimitMaxRaiseTo(pot: potTotal, currentBet: currentBet, toCall: toCall)
            commitAggressive(index, toStreetBet: min(stackCapTo, potCapTo))
        }
    }

    // MARK: - Chip movement

    private func amountToCall(_ index: Int) -> Int {
        max(0, currentBet - seats[index].streetBet)
    }

    /// Moves chips from the seat's stack into the pot to reach `toStreetBet`, updating
    /// all-in and acted flags. Does not touch the bet level.
    private mutating func placeChips(_ index: Int, toStreetBet: Int) {
        let added = toStreetBet - seats[index].streetBet
        seats[index].stack -= added
        seats[index].streetBet = toStreetBet
        seats[index].totalBet += added
        if seats[index].stack == 0 { seats[index].isAllIn = true }
        seats[index].hasActed = true
    }

    /// Handles a bet or raise up to `toStreetBet`: moves the chips, raises the bet level,
    /// marks the bring-in completed, and — for a full raise (or an opening bet, or a
    /// completion) — reopens the action so seats that already acted must respond again.
    private mutating func commitAggressive(_ index: Int, toStreetBet: Int) {
        let wasOpeningBet = currentBet == 0
        let wasIncomplete = !betComplete && !wasOpeningBet   // completing the bring-in
        let increment = toStreetBet - currentBet

        placeChips(index, toStreetBet: toStreetBet)
        currentBet = toStreetBet
        betComplete = true

        let isFullRaise: Bool
        if wasOpeningBet {
            isFullRaise = true
            lastRaiseSize = max(increment, bet)
        } else if wasIncomplete {
            // A completion reaches at least a full bet; a short all-in below it does not.
            isFullRaise = toStreetBet >= bet
            lastRaiseSize = max(bet, toStreetBet - bringIn)
        } else {
            isFullRaise = increment >= lastRaiseSize
            if isFullRaise { lastRaiseSize = increment }
        }

        if isFullRaise {
            for i in seats.indices where i != index && seats[i].canAct { seats[i].hasActed = false }
            actionReopened = true
        } else {
            actionReopened = false
        }
    }

    // MARK: - Round / street progression

    private var nonFoldedCount: Int { seats.reduce(0) { $0 + ($1.hasFolded ? 0 : 1) } }
    private var activePlayerCount: Int { seats.reduce(0) { $0 + ($1.canAct ? 1 : 0) } }

    private func needsToAct(_ index: Int) -> Bool {
        let seat = seats[index]
        return seat.canAct && (!seat.hasActed || seat.streetBet < currentBet)
    }

    private func nextToAct(after index: Int) -> Int? {
        for offset in 1...seatCount {
            let candidate = (index + offset) % seatCount
            if needsToAct(candidate) { return candidate }
        }
        return nil
    }

    private func firstToAct(from start: Int) -> Int? {
        for offset in 0..<seatCount {
            let candidate = (start + offset) % seatCount
            if needsToAct(candidate) { return candidate }
        }
        return nil
    }

    /// Called after every action to advance the state machine.
    private mutating func settle() {
        if nonFoldedCount == 1 { finish(showdown: false); return }
        if let index = actingIndex, let next = nextToAct(after: index) {
            actingIndex = next
            return
        }
        runOutAndFinish()
    }

    /// Advances streets until either betting is required again or the hand is over. When
    /// at most one seat can still act, the remaining streets are dealt straight through
    /// to seventh and the hand goes to showdown.
    private mutating func runOutAndFinish() {
        while true {
            if nonFoldedCount == 1 { finish(showdown: false); return }
            if street == .seventh { finish(showdown: true); return }
            dealNextStreet()
            if activePlayerCount >= 2, let first = firstToAct(from: highestShowingIndex() ?? 0) {
                actingIndex = first
                return
            }
        }
    }

    /// Deals the next street's cards and resets the betting round. Fourth–sixth deal one
    /// UP card to every non-folded seat; seventh deals one DOWN card, falling back to a
    /// single shared COMMUNITY up card if the deck can't cover everyone (D-077).
    private mutating func dealNextStreet() {
        let next = StudStreet(rawValue: street.rawValue + 1)!
        let recipients = seats.indices.filter { !seats[$0].hasFolded }

        if next.dealsUpCard {
            for i in recipients { seats[i].upCards.append(deck.draw()!) }
        } else {
            // Seventh street: one down card each, or one shared community card if short.
            if deck.count >= recipients.count {
                for i in recipients { seats[i].holeCards.append(deck.draw()!) }
            } else if let community = deck.draw() {
                communityCard = community
                for i in recipients { seats[i].holeCards.append(community) }
            }
        }

        street = next
        currentBet = 0
        lastRaiseSize = bet
        actionReopened = true
        betComplete = true   // from fourth street on there is no bring-in; a bet is full
        for i in seats.indices {
            seats[i].streetBet = 0
            seats[i].hasActed = false
        }
    }

    /// The index of the non-folded seat with the highest poker hand SHOWING in its up
    /// cards — the first to act on fourth–seventh street. Ties broken by seat order.
    private func highestShowingIndex() -> Int? {
        var bestIndex: Int?
        var bestKey: [Int] = []
        for i in seats.indices where !seats[i].hasFolded {
            let key = StudShowing.showingKey(seats[i].upCards)
            if bestIndex == nil || StudShowing.isGreater(key, than: bestKey) {
                bestIndex = i
                bestKey = key
            }
        }
        return bestIndex
    }

    // MARK: - Finishing the hand

    private mutating func finish(showdown: Bool) {
        let pots = PotMath.sidePots(from: seats.map {
            PotMath.Contribution(id: $0.id, amount: $0.totalBet, folded: $0.hasFolded)
        })

        var shownHands: [Int: [Card]] = [:]
        var bestHands: [Int: HandRank] = [:]
        if showdown {
            for seat in seats where !seat.hasFolded {
                shownHands[seat.id] = seat.allCards
                bestHands[seat.id] = HandEvaluator.evaluate(seat.allCards)   // best five of seven
            }
        }

        var payouts: [Int: Int] = [:]
        for pot in pots {
            let winners = winnersOf(pot, bestHands: bestHands)
            guard !winners.isEmpty else { continue }
            let ordered = winnersOrderedByPosition(winners)
            for (id, amount) in PotMath.distribute(pot.amount, toWinnersInPriorityOrder: ordered) {
                payouts[id, default: 0] += amount
            }
        }

        for i in seats.indices {
            if let won = payouts[seats[i].id] { seats[i].stack += won }
        }

        result = StudResult(
            pots: pots,
            payouts: payouts,
            finalStacks: Dictionary(uniqueKeysWithValues: seats.map { ($0.id, $0.stack) }),
            wentToShowdown: showdown,
            shownHands: shownHands,
            bestHands: bestHands,
            communityCard: communityCard)
        actingIndex = nil
    }

    private func winnersOf(_ pot: Pot, bestHands: [Int: HandRank]) -> [Int] {
        let eligible = pot.eligibleSeatIDs
        if eligible.count <= 1 { return eligible }

        var best: HandRank?
        var winners: [Int] = []
        for id in eligible {
            guard let rank = bestHands[id] else { continue }
            if best == nil || rank > best! {
                best = rank
                winners = [id]
            } else if rank == best! {
                winners.append(id)
            }
        }
        return winners
    }

    /// Orders winners by seat position, so the odd chip in a split goes to the earliest
    /// seat. Stud has no button, so the first seat is the reference (D-004 spirit).
    func winnersOrderedByPosition(_ ids: [Int]) -> [Int] {
        func position(_ id: Int) -> Int { seats.firstIndex { $0.id == id } ?? Int.max }
        return ids.sorted { position($0) < position($1) }
    }
}
