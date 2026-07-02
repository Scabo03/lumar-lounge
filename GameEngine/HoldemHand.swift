// HoldemHand.swift
// =====================================================================
// The Texas Hold'em No Limit hand engine: a deterministic, turn-based state
// machine that plays a single hand from posting the blinds to awarding the
// pot(s) at showdown (or to the last seat standing).
//
// It is a value type (`struct`) with `mutating` transitions: cheap to snapshot,
// impossible to alias, trivially reproducible. Given the same `seed` and the
// same sequence of actions it always produces the same result (D-005).
//
// Scope (this brick): button/blinds, dealing, four streets, the six actions
// with No Limit min-raise rules, exact stack/pot/side-pot arithmetic, showdown
// and split. Out of scope by design: players-as-people, bots, timers, UI,
// audio, cross-table economy — see ../CLAUDE.md.
//
// Foundation only.

import Foundation

/// A single hand of Texas Hold'em No Limit in progress.
public struct HoldemHand {

    // MARK: Configuration (immutable for the hand)

    public let smallBlind: Int
    public let bigBlind: Int
    /// Index (into `seats`) of the button/dealer.
    public let buttonIndex: Int

    // MARK: Observable state

    public private(set) var seats: [SeatState]
    /// Community cards revealed so far.
    public private(set) var board: [Card]
    public private(set) var street: Street
    /// Highest street bet any seat has made this street (the amount to match).
    public private(set) var currentBet: Int
    /// Index of the seat to act, or `nil` once the hand is complete.
    public private(set) var actingIndex: Int?
    /// The outcome, once the hand has ended.
    public private(set) var result: HandResult?

    // MARK: Internal state

    private var deck: Deck
    /// Size of the last full bet/raise this street — the minimum legal raise
    /// increment for the next raise (No Limit).
    private var lastRaiseSize: Int
    /// Whether the current bet level was set by a *full* bet/raise. An all-in
    /// smaller than a full raise leaves this `false`, which stops seats that
    /// have already acted from re-raising (but they may still call).
    private var actionReopened: Bool

    // MARK: - Init

    /// Sets up a hand: seats the players, posts the blinds, deals the hole
    /// cards and hands the turn to the first seat to act.
    ///
    /// - Parameters:
    ///   - seats: 2–10 seats in clockwise order; each needs a positive stack
    ///     and a unique id.
    ///   - buttonIndex: index of the button within `seats`.
    ///   - smallBlind/bigBlind: positive, with `smallBlind <= bigBlind`.
    ///   - seed: seed for the deterministic shuffle.
    public init(seats seatConfigs: [Seat], buttonIndex: Int, smallBlind: Int, bigBlind: Int, seed: UInt64) {
        precondition((2...10).contains(seatConfigs.count), "Hold'em requires 2–10 seats.")
        precondition(seatConfigs.indices.contains(buttonIndex), "Button index out of range.")
        precondition(smallBlind > 0 && bigBlind > 0 && smallBlind <= bigBlind, "Invalid blinds.")
        precondition(seatConfigs.allSatisfy { $0.stack > 0 }, "Every seat must have a positive stack.")
        precondition(Set(seatConfigs.map(\.id)).count == seatConfigs.count, "Seat ids must be unique.")

        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.buttonIndex = buttonIndex
        self.seats = seatConfigs.map {
            SeatState(id: $0.id, stack: $0.stack, hole: nil, streetBet: 0, totalBet: 0,
                      hasFolded: false, isAllIn: false, hasActed: false)
        }
        self.board = []
        self.street = .preflop
        self.currentBet = 0
        self.actingIndex = nil
        self.result = nil
        self.lastRaiseSize = bigBlind
        self.actionReopened = true
        var deck = Deck()
        deck.shuffle(seed: seed)
        self.deck = deck

        dealHoleCards()
        postBlinds()
        beginPreflop()
    }

    // MARK: - Positions (derived from the button)

    private var seatCount: Int { seats.count }
    private func seatAfter(_ index: Int) -> Int { (index + 1) % seatCount }

    /// Heads-up: the button is the small blind. Otherwise SB is left of button.
    private var smallBlindIndex: Int { seatCount == 2 ? buttonIndex : seatAfter(buttonIndex) }
    private var bigBlindIndex: Int { seatAfter(smallBlindIndex) }

    // MARK: - Setup steps

    /// Deals two hole cards to each seat, one at a time starting from the small
    /// blind. The dealing order is fixed (hence reproducible); it does not
    /// affect fairness since the deck is already randomly shuffled.
    private mutating func dealHoleCards() {
        var holes: [[Card]] = Array(repeating: [], count: seatCount)
        for _ in 0..<2 {
            for offset in 0..<seatCount {
                let index = (smallBlindIndex + offset) % seatCount
                holes[index].append(deck.draw()!)
            }
        }
        for i in seats.indices {
            seats[i].hole = Hand(holes[i][0], holes[i][1])
        }
    }

    private mutating func postBlinds() {
        postBlind(at: smallBlindIndex, amount: smallBlind)
        postBlind(at: bigBlindIndex, amount: bigBlind)
        // The nominal big blind is the amount others must call, even if the big
        // blind was posted short (all-in for less).
        currentBet = bigBlind
        lastRaiseSize = bigBlind
        actionReopened = true
    }

    /// Posts a forced blind, going all-in if the stack cannot cover it. Posting
    /// a blind is not "acting", so `hasActed` stays false (the big blind keeps
    /// its option to raise).
    private mutating func postBlind(at index: Int, amount: Int) {
        let posted = min(amount, seats[index].stack)
        seats[index].stack -= posted
        seats[index].streetBet = posted
        seats[index].totalBet += posted
        if seats[index].stack == 0 { seats[index].isAllIn = true }
    }

    private mutating func beginPreflop() {
        if activePlayerCount >= 2, let first = firstToAct(from: seatAfter(bigBlindIndex)) {
            actingIndex = first
        } else {
            // Everyone (or all but one) is already all-in: no betting to do.
            actingIndex = nil
            runOutAndFinish()
        }
    }

    // MARK: - Public queries

    /// The id of the seat to act, if any.
    public var actingSeatID: Int? {
        guard let actingIndex else { return nil }
        return seats[actingIndex].id
    }

    public var isComplete: Bool { result != nil }

    /// The legal actions for the seat currently on turn, or `nil` if the hand
    /// is complete.
    public func legalActions() -> LegalActions? {
        guard let index = actingIndex else { return nil }
        let seat = seats[index]
        let toCall = max(0, currentBet - seat.streetBet)
        let maxTo = seat.streetBet + seat.stack

        let canCheck = toCall == 0
        let canCall = toCall > 0
        let canBet = currentBet == 0 && seat.stack > 0
        let canReopen = !seat.hasActed || actionReopened
        // A raise needs an existing bet, room above it, and the action open.
        let canRaise = currentBet > 0 && maxTo > currentBet && canReopen

        return LegalActions(
            seatID: seat.id,
            canFold: true,
            canCheck: canCheck,
            canCall: canCall,
            callAmount: min(toCall, seat.stack),
            canBet: canBet,
            minBetTo: min(bigBlind, seat.stack),
            maxBetTo: seat.stack,
            canRaise: canRaise,
            minRaiseTo: min(currentBet + lastRaiseSize, maxTo),
            maxRaiseTo: maxTo,
            canAllIn: seat.stack > 0
        )
    }

    // MARK: - Applying actions

    /// Applies `action` for the seat on turn and advances the hand.
    /// - Throws: `ActionError` if the action is illegal in the current state.
    public mutating func apply(_ action: Action) throws {
        guard result == nil, let index = actingIndex else { throw ActionError.handComplete }

        switch action {
        case .fold:            applyFold(index)
        case .check:           try applyCheck(index)
        case .call:            applyCall(index)
        case .bet(let to):     try applyBet(index, to: to)
        case .raise(let to):   try applyRaise(index, to: to)
        case .allIn:           try applyAllIn(index)
        }

        settle()
    }

    private mutating func applyFold(_ index: Int) {
        seats[index].hasFolded = true
        seats[index].hasActed = true
    }

    private mutating func applyCheck(_ index: Int) throws {
        guard amountToCall(index) == 0 else { throw ActionError.cannotCheckFacingBet }
        seats[index].hasActed = true
    }

    private mutating func applyCall(_ index: Int) {
        // Guarded by validation elsewhere; a call with nothing to call is a
        // programmer error routed here only from `apply`, so check defensively.
        let toCall = amountToCall(index)
        let pay = min(toCall, seats[index].stack)
        placeChips(index, toStreetBet: seats[index].streetBet + pay)
    }

    private mutating func applyBet(_ index: Int, to: Int) throws {
        guard currentBet == 0 else { throw ActionError.cannotBetFacingBet }
        guard to > 0 else { throw ActionError.nonPositiveAmount }
        let maxTo = seats[index].streetBet + seats[index].stack
        guard to <= maxTo else { throw ActionError.amountExceedsStack(maximumTo: maxTo) }
        let isAllInBet = to == maxTo
        guard to >= bigBlind || isAllInBet else { throw ActionError.betBelowMinimum(minimum: bigBlind) }
        commitAggressive(index, toStreetBet: to)
    }

    private mutating func applyRaise(_ index: Int, to: Int) throws {
        guard currentBet > 0 else { throw ActionError.cannotRaiseNothingToRaise }
        guard to > currentBet else { throw ActionError.raiseBelowMinimum(minimumTo: currentBet + lastRaiseSize) }
        let maxTo = seats[index].streetBet + seats[index].stack
        guard to <= maxTo else { throw ActionError.amountExceedsStack(maximumTo: maxTo) }
        guard !seats[index].hasActed || actionReopened else { throw ActionError.actionNotReopened }
        let isAllInRaise = to == maxTo
        let increment = to - currentBet
        guard increment >= lastRaiseSize || isAllInRaise else {
            throw ActionError.raiseBelowMinimum(minimumTo: currentBet + lastRaiseSize)
        }
        commitAggressive(index, toStreetBet: to)
    }

    private mutating func applyAllIn(_ index: Int) throws {
        let target = seats[index].streetBet + seats[index].stack
        if currentBet == 0 {
            // Opening all-in bet (min-bet rule waived when all-in).
            commitAggressive(index, toStreetBet: target)
        } else if target <= currentBet {
            // Cannot cover the call: an all-in call. Never reopens the action.
            placeChips(index, toStreetBet: target)
        } else {
            // All-in that exceeds the bet is a raise: it must be open to us,
            // otherwise the player can only call — not shove over — the bet.
            guard !seats[index].hasActed || actionReopened else { throw ActionError.actionNotReopened }
            commitAggressive(index, toStreetBet: target)
        }
    }

    // MARK: - Chip movement

    private func amountToCall(_ index: Int) -> Int {
        max(0, currentBet - seats[index].streetBet)
    }

    /// Moves chips from the seat's stack into the pot to reach `toStreetBet`,
    /// updating all-in and acted flags. Does not touch the bet level.
    private mutating func placeChips(_ index: Int, toStreetBet: Int) {
        let added = toStreetBet - seats[index].streetBet
        seats[index].stack -= added
        seats[index].streetBet = toStreetBet
        seats[index].totalBet += added
        if seats[index].stack == 0 { seats[index].isAllIn = true }
        seats[index].hasActed = true
    }

    /// Handles a bet or raise up to `toStreetBet`: moves the chips, raises the
    /// bet level, and — for a full raise (or an opening bet) — reopens the
    /// action so seats that already acted must respond again.
    private mutating func commitAggressive(_ index: Int, toStreetBet: Int) {
        let wasOpeningBet = currentBet == 0
        let increment = toStreetBet - currentBet
        let isFullRaise = wasOpeningBet || increment >= lastRaiseSize

        placeChips(index, toStreetBet: toStreetBet)
        currentBet = toStreetBet

        if isFullRaise {
            // An opening bet's increment is its full size; keep the min raise at
            // least a big blind for a short all-in open.
            lastRaiseSize = wasOpeningBet ? max(increment, bigBlind) : increment
            for i in seats.indices where i != index && seats[i].canAct {
                seats[i].hasActed = false
            }
            actionReopened = true
        } else {
            // Incomplete all-in raise: does not reopen the betting.
            actionReopened = false
        }
    }

    // MARK: - Round / street progression

    private var nonFoldedCount: Int { seats.reduce(0) { $0 + ($1.hasFolded ? 0 : 1) } }
    private var activePlayerCount: Int { seats.reduce(0) { $0 + ($1.canAct ? 1 : 0) } }

    /// A seat still owes an action if it can act and either hasn't acted yet or
    /// hasn't matched the current bet.
    private func needsToAct(_ index: Int) -> Bool {
        let seat = seats[index]
        return seat.canAct && (!seat.hasActed || seat.streetBet < currentBet)
    }

    /// Next seat (clockwise, strictly after `index`) that still owes an action.
    private func nextToAct(after index: Int) -> Int? {
        for offset in 1...seatCount {
            let candidate = (index + offset) % seatCount
            if needsToAct(candidate) { return candidate }
        }
        return nil
    }

    /// First seat that owes an action, scanning clockwise from `start` inclusive.
    private func firstToAct(from start: Int) -> Int? {
        for offset in 0..<seatCount {
            let candidate = (start + offset) % seatCount
            if needsToAct(candidate) { return candidate }
        }
        return nil
    }

    /// Called after every action to advance the state machine.
    private mutating func settle() {
        // Everyone folded to one seat: the hand ends without a showdown.
        if nonFoldedCount == 1 { finish(showdown: false); return }
        // Betting round still in progress: hand the turn to the next seat.
        if let index = actingIndex, let next = nextToAct(after: index) {
            actingIndex = next
            return
        }
        // Betting round complete: move to the next street (or showdown).
        runOutAndFinish()
    }

    /// Advances streets until either betting is required again or the hand is
    /// over. When at most one seat can still act, the remaining board is dealt
    /// straight to the river and the hand goes to showdown.
    private mutating func runOutAndFinish() {
        while true {
            if nonFoldedCount == 1 { finish(showdown: false); return }
            if street == .river { finish(showdown: true); return }
            dealNextStreet()
            if activePlayerCount >= 2, let first = firstToAct(from: seatAfter(buttonIndex)) {
                actingIndex = first
                return
            }
            // No one (or only one) can act: keep dealing.
        }
    }

    /// Reveals the next street's community cards and resets the betting round.
    private mutating func dealNextStreet() {
        switch street {
        case .preflop:
            board.append(contentsOf: [deck.draw()!, deck.draw()!, deck.draw()!])
            street = .flop
        case .flop:
            board.append(deck.draw()!)
            street = .turn
        case .turn:
            board.append(deck.draw()!)
            street = .river
        case .river:
            preconditionFailure("No street after the river.")
        }
        currentBet = 0
        lastRaiseSize = bigBlind
        actionReopened = true
        for i in seats.indices {
            seats[i].streetBet = 0
            seats[i].hasActed = false
        }
    }

    // MARK: - Finishing the hand

    private mutating func finish(showdown: Bool) {
        let pots = PotMath.sidePots(from: seats.map {
            PotMath.Contribution(id: $0.id, amount: $0.totalBet, folded: $0.hasFolded)
        })

        var shownHands: [Int: Hand] = [:]
        var bestHands: [Int: HandRank] = [:]
        if showdown {
            for seat in seats where !seat.hasFolded {
                guard let hole = seat.hole else { continue }
                shownHands[seat.id] = hole
                bestHands[seat.id] = HandEvaluator.evaluate(hole.cards + board)
            }
        }

        var payouts: [Int: Int] = [:]
        for pot in pots {
            let winners = winnersOf(pot, bestHands: bestHands)
            guard !winners.isEmpty else { continue } // cannot happen in valid play
            let ordered = winnersOrderedFromButton(winners)
            for (id, amount) in PotMath.distribute(pot.amount, toWinnersInPriorityOrder: ordered) {
                payouts[id, default: 0] += amount
            }
        }

        for i in seats.indices {
            if let won = payouts[seats[i].id] { seats[i].stack += won }
        }

        result = HandResult(
            pots: pots,
            payouts: payouts,
            finalStacks: Dictionary(uniqueKeysWithValues: seats.map { ($0.id, $0.stack) }),
            wentToShowdown: showdown,
            board: board,
            shownHands: shownHands,
            bestHands: bestHands
        )
        actingIndex = nil
    }

    /// The winning seat ids for a pot: the single eligible seat, or those tied
    /// for the best evaluated hand among the eligible seats.
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

    /// Orders winners clockwise starting from the seat left of the button, so
    /// the odd chip in a split goes to the earliest such seat (D-004).
    /// Internal (not private) so the odd-chip ordering can be unit-tested.
    func winnersOrderedFromButton(_ ids: [Int]) -> [Int] {
        func distanceFromButton(_ id: Int) -> Int {
            let index = seats.firstIndex { $0.id == id }!
            return (index - (buttonIndex + 1) + seatCount) % seatCount
        }
        return ids.sorted { distanceFromButton($0) < distanceFromButton($1) }
    }

    // MARK: - Button rotation (helper for the next hand)

    /// The button position for the next hand: the next seat clockwise.
    ///
    /// This is intentionally simple. Skipping seats that busted or left the
    /// table is a table/session concern that belongs to GameWorld (D-006), not
    /// to a single pure hand.
    public static func nextButtonIndex(after currentButton: Int, seatCount: Int) -> Int {
        precondition(seatCount >= 2, "Need at least two seats.")
        return (currentButton + 1) % seatCount
    }
}
