// FiveCardDrawHand.swift
// =====================================================================
// The Five-Card Draw hand engine: a deterministic, turn-based state machine that
// plays a single deal of traditional "Jacks or Better" draw poker, from posting
// the antes to awarding the pot at showdown (or declaring the deal passed in).
//
// This is a second, independent game engine (D-038). It shares nothing with the
// Texas Hold'em engine beyond the foundational M1.1 types and the game-agnostic
// chip arithmetic (`PotMath`/`Pot`). Like `HoldemHand` it is a value type with
// `mutating` transitions — cheap to snapshot, impossible to alias, reproducible:
// the same `seed` and the same sequence of actions always produce the same result.
//
// The complete rule set (D-039..D-041):
//   • Ante from every seat, no blinds.
//   • Two betting rounds — one before the draw (small bet) and one after
//     (big bet) — with LIMIT sizing and a cap of three raises per round.
//   • Jacks-or-better to open: opening is on the honour system (anyone may bet)
//     and enforced at showdown ("show your openers", D-039).
//   • The draw: each live seat discards 0–4 cards and draws replacements.
//   • Pass-and-out with a progressive pot: if no one opens, the deal is void and
//     its antes carry into the next deal (variant B, D-040).
//   • Showdown on exactly five cards via `HandEvaluator`, with opener disqualification.
//
// Foundation only.

import Foundation

/// A single deal of Five-Card Draw ("Jacks or Better") in progress.
public struct FiveCardDrawHand {

    // MARK: Configuration (immutable for the deal)

    public let ante: Int
    public let smallBet: Int
    public let bigBet: Int
    /// Index (into `seats`) of the button/dealer.
    public let buttonIndex: Int
    /// Chips carried into this deal from prior passed-in deals (variant B). They
    /// belong to no one and join the main pot when the deal is actually played.
    public let carryPot: Int

    // MARK: Observable state

    public private(set) var seats: [DrawSeatState]
    public private(set) var phase: DrawPhase
    /// Highest street bet any seat has made this round (the amount to match).
    public private(set) var currentBet: Int
    /// Index of the seat to act in a betting round, or `nil` outside one.
    public private(set) var actingIndex: Int?
    /// Index of the seat whose draw it is during `.draw`, or `nil` otherwise.
    public private(set) var drawingIndex: Int?
    /// The outcome, once the deal has completed.
    public private(set) var result: DrawResult?

    // MARK: Internal state

    private var deck: Deck
    /// Number of aggressive actions taken this round (bet + raises). The cap is
    /// four escalations: bet, raise, re-raise, cap — then only call/fold (D-041).
    private var aggressiveCount: Int
    /// Whether the current bet level was set by a *full* bet/raise. A short all-in
    /// below a full raise leaves this `false`, which stops seats that already
    /// acted from re-raising (they may still call).
    private var actionReopened: Bool
    /// Id of the seat that opened this deal, if any (mirrors `seats[…].isOpener`).
    private var openerSeatID: Int?

    // MARK: - Init

    /// Sets up a deal: seats the players, posts the antes, deals five cards each
    /// and opens the first betting round.
    ///
    /// - Parameters:
    ///   - seats: 2–7 seats in clockwise order; each needs a positive stack and a
    ///     unique id. (The traditional target is four: one human plus three bots.)
    ///   - buttonIndex: index of the button within `seats`.
    ///   - ante: the fixed ante every seat posts (> 0).
    ///   - smallBet: the fixed bet/raise unit before the draw (> 0).
    ///   - bigBet: the fixed bet/raise unit after the draw (traditionally 2×
    ///     small bet; must be ≥ small bet).
    ///   - seed: seed for the deterministic shuffle.
    ///   - carryPot: chips carried in from prior passed-in deals (default 0).
    public init(seats seatConfigs: [DrawSeat],
                buttonIndex: Int,
                ante: Int,
                smallBet: Int,
                bigBet: Int,
                seed: UInt64,
                carryPot: Int = 0) {
        precondition((2...7).contains(seatConfigs.count), "Five-Card Draw seats 2–7 players.")
        precondition(seatConfigs.indices.contains(buttonIndex), "Button index out of range.")
        precondition(ante > 0 && smallBet > 0 && bigBet >= smallBet, "Invalid ante/bet sizes.")
        precondition(seatConfigs.allSatisfy { $0.stack > 0 }, "Every seat must have a positive stack.")
        precondition(Set(seatConfigs.map(\.id)).count == seatConfigs.count, "Seat ids must be unique.")
        precondition(carryPot >= 0, "Carry pot cannot be negative.")

        self.ante = ante
        self.smallBet = smallBet
        self.bigBet = bigBet
        self.buttonIndex = buttonIndex
        self.carryPot = carryPot
        self.seats = seatConfigs.map {
            DrawSeatState(id: $0.id, stack: $0.stack, cards: [], streetBet: 0, totalBet: 0,
                          hasFolded: false, isAllIn: false, isOpener: false, openers: nil,
                          discardCount: 0, hasDrawn: false, hasActed: false)
        }
        self.phase = .firstBet
        self.currentBet = 0
        self.actingIndex = nil
        self.drawingIndex = nil
        self.result = nil
        self.aggressiveCount = 0
        self.actionReopened = true
        self.openerSeatID = nil
        var deck = Deck()
        deck.shuffle(seed: seed)
        self.deck = deck

        postAntes()
        dealCards()
        beginFirstBet()
    }

    // MARK: - Positions

    private var seatCount: Int { seats.count }
    private func seatAfter(_ index: Int) -> Int { (index + 1) % seatCount }

    // MARK: - Setup steps

    /// Every seat posts the ante (all-in for less if the stack can't cover it).
    /// The ante is dead money: it goes to the pot (counted in `totalBet`) but is
    /// not part of any betting round, so it never affects the amount to call.
    private mutating func postAntes() {
        for i in seats.indices {
            let posted = min(ante, seats[i].stack)
            seats[i].stack -= posted
            seats[i].totalBet += posted
            if seats[i].stack == 0 { seats[i].isAllIn = true }
        }
    }

    /// Deals five cards to each seat, one at a time from the seat left of the
    /// button. The order is fixed (hence reproducible); fairness comes from the
    /// already-random shuffle.
    private mutating func dealCards() {
        var hands: [[Card]] = Array(repeating: [], count: seatCount)
        let start = seatAfter(buttonIndex)
        for _ in 0..<5 {
            for offset in 0..<seatCount {
                let index = (start + offset) % seatCount
                hands[index].append(deck.draw()!)
            }
        }
        for i in seats.indices {
            seats[i].cards = FiveCardDrawHand.sorted(hands[i])
        }
    }

    private mutating func beginFirstBet() {
        // First to act before the draw is the seat left of the button.
        if let first = firstToAct(from: seatAfter(buttonIndex)) {
            actingIndex = first
        } else if nonFoldedCount >= 2 {
            // No one can bet (everyone is all-in on the ante): there is no open to
            // decline, so this is not a pass-in — run the draw and show down.
            beginDraw()
        } else {
            // A lone seat with everyone else folded/absent: it takes the antes.
            finishFoldOut()
        }
    }

    // MARK: - Public queries

    /// The id of the seat to act in a betting round, if any.
    public var actingSeatID: Int? {
        guard let actingIndex else { return nil }
        return seats[actingIndex].id
    }

    /// The id of the seat whose draw it is, if in the draw phase.
    public var drawingSeatID: Int? {
        guard let drawingIndex else { return nil }
        return seats[drawingIndex].id
    }

    public var isComplete: Bool { result != nil }

    /// Total chips in the pot: everything wagered so far plus the carried pot.
    public var pot: Int {
        seats.reduce(carryPot) { $0 + $1.totalBet }
    }

    /// Cards still in the deck (dealt cards and drawn replacements have left it).
    public var cardsRemaining: Int { deck.count }

    /// The fixed bet/raise unit for the current round.
    private var betUnit: Int {
        phase == .secondBet ? bigBet : smallBet
    }

    /// Whether a seat's five cards are jacks-or-better (i.e. an open would be
    /// provable at showdown). "Or better" includes any higher category, per the
    /// traditional rule that any hand at least as strong as a pair of jacks opens.
    public func qualifiesToOpen(_ cards: [Card]) -> Bool {
        FiveCardDrawHand.qualifies(cards)
    }

    /// The ids of the currently seated players who hold jacks-or-better and could
    /// therefore open the pot legitimately right now.
    public func seatsQualifiedToOpen() -> [Int] {
        seats.filter { !$0.hasFolded && FiveCardDrawHand.qualifies($0.cards) }.map(\.id)
    }

    /// The legal betting actions for the seat on turn, or `nil` if not currently
    /// in a betting round with a seat to act.
    public func legalActions() -> DrawLegalActions? {
        guard phase == .firstBet || phase == .secondBet, let index = actingIndex else { return nil }
        let seat = seats[index]
        let toCall = max(0, currentBet - seat.streetBet)
        let maxTo = seat.streetBet + seat.stack
        let canReopen = !seat.hasActed || actionReopened
        let underCap = aggressiveCount < 4

        return DrawLegalActions(
            seatID: seat.id,
            canFold: true,
            canCheck: toCall == 0,
            canCall: toCall > 0 && seat.stack > 0,
            callAmount: min(toCall, seat.stack),
            canBet: currentBet == 0 && seat.stack > 0,
            canRaise: currentBet > 0 && maxTo > currentBet && underCap && canReopen,
            betUnit: betUnit,
            raisesRemaining: max(0, 4 - aggressiveCount),
            hasOpeners: FiveCardDrawHand.qualifies(seat.cards)
        )
    }

    /// The exchange options for the seat whose draw it is, or `nil` otherwise.
    public func drawOptions() -> DrawOptions? {
        guard phase == .draw, let index = drawingIndex else { return nil }
        return DrawOptions(seatID: seats[index].id, cards: seats[index].cards, maxDiscards: 4)
    }

    // MARK: - Applying betting actions

    /// Applies a betting `action` for the seat on turn and advances the deal.
    /// - Throws: `DrawActionError` if the action is illegal in the current state.
    public mutating func apply(_ action: DrawAction) throws {
        guard result == nil else { throw DrawActionError.handComplete }
        guard phase == .firstBet || phase == .secondBet, let index = actingIndex else {
            throw DrawActionError.notInBettingPhase
        }

        switch action {
        case .fold:  applyFold(index)
        case .check: try applyCheck(index)
        case .call:  try applyCall(index)
        case .bet:   try applyBet(index)
        case .raise: try applyRaise(index)
        }

        settle()
    }

    private mutating func applyFold(_ index: Int) {
        seats[index].hasFolded = true
        seats[index].hasActed = true
    }

    private mutating func applyCheck(_ index: Int) throws {
        guard amountToCall(index) == 0 else { throw DrawActionError.cannotCheckFacingBet }
        seats[index].hasActed = true
    }

    private mutating func applyCall(_ index: Int) throws {
        let toCall = amountToCall(index)
        guard toCall > 0 else { throw DrawActionError.cannotCallNothingToCall }
        let pay = min(toCall, seats[index].stack)
        placeChips(index, toStreetBet: seats[index].streetBet + pay)
    }

    private mutating func applyBet(_ index: Int) throws {
        guard currentBet == 0 else { throw DrawActionError.cannotBetFacingBet }
        guard seats[index].stack > 0 else { throw DrawActionError.noChipsToBet }
        // Opening on the honour system: record whether the open was legitimate.
        recordOpen(index)
        let to = min(betUnit, seats[index].streetBet + seats[index].stack)
        commitAggressive(index, toStreetBet: to)
    }

    private mutating func applyRaise(_ index: Int) throws {
        guard currentBet > 0 else { throw DrawActionError.cannotRaiseNothingToRaise }
        guard aggressiveCount < 4 else { throw DrawActionError.raiseCapReached }
        let maxTo = seats[index].streetBet + seats[index].stack
        guard maxTo > currentBet else { throw DrawActionError.cannotRaiseNothingToRaise }
        guard !seats[index].hasActed || actionReopened else { throw DrawActionError.actionNotReopened }
        let to = min(currentBet + betUnit, maxTo)
        commitAggressive(index, toStreetBet: to)
    }

    /// Records an open: marks the seat as the opener and snapshots the cards that
    /// prove jacks-or-better (`nil` if it opened without the goods — a bluff-open
    /// that will be exposed at showdown, D-039).
    private mutating func recordOpen(_ index: Int) {
        seats[index].isOpener = true
        seats[index].openers = FiveCardDrawHand.openerProof(seats[index].cards)
        openerSeatID = seats[index].id
    }

    // MARK: - Chip movement

    private func amountToCall(_ index: Int) -> Int {
        max(0, currentBet - seats[index].streetBet)
    }

    /// Moves chips into the pot to reach `toStreetBet`, updating all-in/acted
    /// flags. Does not touch the bet level.
    private mutating func placeChips(_ index: Int, toStreetBet: Int) {
        let added = toStreetBet - seats[index].streetBet
        seats[index].stack -= added
        seats[index].streetBet = toStreetBet
        seats[index].totalBet += added
        if seats[index].stack == 0 { seats[index].isAllIn = true }
        seats[index].hasActed = true
    }

    /// Handles a bet or raise up to `toStreetBet`: moves the chips, raises the bet
    /// level, counts the escalation toward the cap, and — for a full raise (or an
    /// opening bet) — reopens the action for seats that had already acted.
    private mutating func commitAggressive(_ index: Int, toStreetBet: Int) {
        let wasOpeningBet = currentBet == 0
        let increment = toStreetBet - currentBet
        let isFullRaise = wasOpeningBet || increment >= betUnit

        placeChips(index, toStreetBet: toStreetBet)
        currentBet = toStreetBet
        aggressiveCount += 1

        if isFullRaise {
            for i in seats.indices where i != index && seats[i].canAct {
                seats[i].hasActed = false
            }
            actionReopened = true
        } else {
            // Incomplete all-in raise: does not reopen the betting.
            actionReopened = false
        }
    }

    // MARK: - Round progression

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

    /// Called after every betting action to advance the state machine.
    private mutating func settle() {
        // Everyone folded to one seat.
        if nonFoldedCount == 1 {
            if phase == .firstBet && currentBet == 0 {
                // Nobody opened and all but one mucked: still a void deal.
                passIn()
            } else {
                finishFoldOut()
            }
            return
        }
        // Betting round still in progress: pass the turn on.
        if let index = actingIndex, let next = nextToAct(after: index) {
            actingIndex = next
            return
        }
        // Betting round complete.
        actingIndex = nil
        if phase == .firstBet {
            if currentBet == 0 {
                passIn()          // no one opened → pass-and-out
            } else {
                beginDraw()
            }
        } else {
            finishShowdown()
        }
    }

    // MARK: - Draw phase

    private mutating func beginDraw() {
        phase = .draw
        drawingIndex = firstLiveSeat(from: seatAfter(buttonIndex))
        // With at most one live seat we would have finished already; guard anyway.
        if drawingIndex == nil { finishShowdown() }
    }

    /// Applies the seat-on-turn's card exchange: discards `cards` (0…4 of the
    /// seat's own cards) and draws that many replacements from the deck.
    /// - Throws: `DrawExchangeError` if it isn't this seat's draw, or the cards
    ///   aren't a valid subset of its hand.
    public mutating func discard(_ cards: [Card]) throws {
        guard result == nil else { throw DrawExchangeError.notInDrawPhase }
        guard phase == .draw, let index = drawingIndex else { throw DrawExchangeError.notInDrawPhase }
        guard cards.count <= 4 else { throw DrawExchangeError.tooManyDiscards }

        // Validate the discards are distinct cards actually held.
        var remaining = seats[index].cards
        for card in cards {
            guard let pos = remaining.firstIndex(of: card) else { throw DrawExchangeError.cardNotHeld(card) }
            remaining.remove(at: pos)
        }

        // Draw replacements from the top of the deck. With ≤7 seats the deck can
        // never run dry (7×5 dealt + 7×4 drawn = 63 > 52 only in the abstract; in
        // practice far fewer), but guard defensively.
        for _ in 0..<cards.count {
            if let drawn = deck.draw() { remaining.append(drawn) }
        }
        seats[index].cards = FiveCardDrawHand.sorted(remaining)
        seats[index].discardCount = cards.count
        seats[index].hasDrawn = true

        // Advance to the next live seat that hasn't drawn, or start round two.
        drawingIndex = nextLiveSeatToDraw(after: index)
        if drawingIndex == nil { beginSecondBet() }
    }

    private func firstLiveSeat(from start: Int) -> Int? {
        for offset in 0..<seatCount {
            let candidate = (start + offset) % seatCount
            if seats[candidate].isLive { return candidate }
        }
        return nil
    }

    private func nextLiveSeatToDraw(after index: Int) -> Int? {
        for offset in 1...seatCount {
            let candidate = (index + offset) % seatCount
            if seats[candidate].isLive && !seats[candidate].hasDrawn { return candidate }
        }
        return nil
    }

    // MARK: - Second betting round

    private mutating func beginSecondBet() {
        phase = .secondBet
        currentBet = 0
        aggressiveCount = 0
        actionReopened = true
        for i in seats.indices {
            seats[i].streetBet = 0
            seats[i].hasActed = false
        }
        // First to act after the draw is the first live seat left of the button.
        if activePlayerCount >= 2, let first = firstToAct(from: seatAfter(buttonIndex)) {
            actingIndex = first
        } else {
            // At most one seat can bet (the rest are all-in): straight to showdown.
            actingIndex = nil
            finishShowdown()
        }
    }

    // MARK: - Finishing the deal

    /// The deal is void: no one opened. Its antes (and any carried pot) roll into
    /// the next deal. No chips are returned to stacks — the driver reseats the
    /// same stacks and passes `carriedPot` into the next `FiveCardDrawHand`.
    private mutating func passIn() {
        actingIndex = nil
        drawingIndex = nil
        phase = .complete
        result = DrawResult(
            outcome: .passedIn,
            pots: [],
            payouts: [:],
            finalStacks: Dictionary(uniqueKeysWithValues: seats.map { ($0.id, $0.stack) }),
            wentToShowdown: false,
            revealedHands: [:],
            bestHands: [:],
            openerSeatID: openerSeatID,
            openerDisqualified: false,
            carriedPot: pot
        )
    }

    /// Everyone folded to a single live seat: it wins without a showdown. The
    /// opener is NOT required to prove openers here — a bluff-open that takes the
    /// pot uncontested is a successful steal (D-039).
    private mutating func finishFoldOut() {
        finish(showdown: false, disqualifyOpener: false)
    }

    /// Two or more seats reach showdown. The opener, if present and unable to
    /// prove openers, is disqualified and cannot win any pot (D-039).
    private mutating func finishShowdown() {
        let openerReached = openerSeatID.flatMap { id in seats.first { $0.id == id } }?.isLive ?? false
        let openerInvalid = openerReached
            && (seats.first { $0.id == openerSeatID }?.openers == nil)
        finish(showdown: true, disqualifyOpener: openerInvalid)
    }

    private mutating func finish(showdown: Bool, disqualifyOpener: Bool) {
        // Build the pots from every seat's total contribution; fold the dead
        // carry-pot into the main pot so it is won normally.
        var pots = PotMath.sidePots(from: seats.map {
            PotMath.Contribution(id: $0.id, amount: $0.totalBet, folded: $0.hasFolded)
        })
        if carryPot > 0 {
            if pots.isEmpty {
                pots = [Pot(amount: carryPot, eligibleSeatIDs: seats.filter { !$0.hasFolded }.map(\.id).sorted())]
            } else {
                pots[0] = Pot(amount: pots[0].amount + carryPot, eligibleSeatIDs: pots[0].eligibleSeatIDs)
            }
        }

        var revealed: [Int: [Card]] = [:]
        var bestHands: [Int: HandRank] = [:]
        if showdown {
            for seat in seats where !seat.hasFolded {
                revealed[seat.id] = seat.cards
                bestHands[seat.id] = HandEvaluator.evaluate(seat.cards)
            }
        }

        let disqualified: Set<Int> = disqualifyOpener ? Set(openerSeatID.map { [$0] } ?? []) : []

        var payouts: [Int: Int] = [:]
        for pot in pots {
            var winners = winnersOf(pot, bestHands: bestHands, excluding: disqualified)
            // A pot whose only claimants were disqualified falls to the best
            // remaining live hand overall, so no chips vanish (D-039).
            if winners.isEmpty {
                let pool = seats.filter { !$0.hasFolded && !disqualified.contains($0.id) }.map(\.id)
                winners = bestAmong(pool, bestHands: bestHands)
            }
            guard !winners.isEmpty else { continue }
            let ordered = winnersOrderedFromButton(winners)
            for (id, amount) in PotMath.distribute(pot.amount, toWinnersInPriorityOrder: ordered) {
                payouts[id, default: 0] += amount
            }
        }

        for i in seats.indices {
            if let won = payouts[seats[i].id] { seats[i].stack += won }
        }

        actingIndex = nil
        drawingIndex = nil
        phase = .complete
        result = DrawResult(
            outcome: showdown ? .showdown : .foldOut,
            pots: pots,
            payouts: payouts,
            finalStacks: Dictionary(uniqueKeysWithValues: seats.map { ($0.id, $0.stack) }),
            wentToShowdown: showdown,
            revealedHands: revealed,
            bestHands: bestHands,
            openerSeatID: openerSeatID,
            openerDisqualified: disqualifyOpener,
            carriedPot: 0
        )
    }

    /// The winning seat ids for a pot: the eligible seats (minus any disqualified),
    /// reduced to those tied for the best evaluated hand. With no showdown ranks
    /// (a fold-out), the single eligible seat wins.
    private func winnersOf(_ pot: Pot, bestHands: [Int: HandRank], excluding disqualified: Set<Int>) -> [Int] {
        let eligible = pot.eligibleSeatIDs.filter { !disqualified.contains($0) }
        if bestHands.isEmpty { return eligible }        // fold-out
        return bestAmong(eligible, bestHands: bestHands)
    }

    /// The subset of `ids` tied for the strongest evaluated hand.
    private func bestAmong(_ ids: [Int], bestHands: [Int: HandRank]) -> [Int] {
        var best: HandRank?
        var winners: [Int] = []
        for id in ids {
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

    /// Orders winners clockwise from the seat left of the button, so the odd chip
    /// in a split goes to the earliest such seat (the standard house rule, as in
    /// the Hold'em engine's D-004). Internal so it can be unit-tested.
    func winnersOrderedFromButton(_ ids: [Int]) -> [Int] {
        func distanceFromButton(_ id: Int) -> Int {
            let index = seats.firstIndex { $0.id == id }!
            return (index - (buttonIndex + 1) + seatCount) % seatCount
        }
        return ids.sorted { distanceFromButton($0) < distanceFromButton($1) }
    }

    // MARK: - Button rotation (helper for the next played deal)

    /// The button position for the next *played* deal: the next seat clockwise.
    /// Passed-in deals do not rotate the button (the driver simply re-deals with
    /// the same button and the carried pot, D-040). Skipping busted/absent seats
    /// is a table concern for the future GameWorld driver, not this pure deal.
    public static func nextButtonIndex(after currentButton: Int, seatCount: Int) -> Int {
        precondition(seatCount >= 2, "Need at least two seats.")
        return (currentButton + 1) % seatCount
    }

    // MARK: - Static helpers

    /// Cards sorted by descending rank, breaking ties by suit order, for a stable
    /// and readable hand presentation.
    static func sorted(_ cards: [Card]) -> [Card] {
        cards.sorted { a, b in
            a.rank != b.rank ? a.rank > b.rank : a.suit.rawValue < b.suit.rawValue
        }
    }

    /// Whether five cards are at least a pair of jacks — the opening threshold.
    /// "Or better" means any higher category also qualifies (a straight, a flush,
    /// trips of any rank, etc.), per the traditional rule.
    static func qualifies(_ cards: [Card]) -> Bool {
        guard cards.count == 5 else { return false }
        let rank = HandEvaluator.evaluate(cards)
        if rank.category > .pair { return true }
        if rank.category == .pair { return (rank.tiebreakers.first ?? 0) >= Rank.jack.rawValue }
        return false
    }

    /// The cards that prove an open, or `nil` if the hand does not qualify. For a
    /// qualifying pair (jacks or better) it is the two paired cards; for a higher
    /// combination without such a pair (e.g. a straight) it is the whole hand.
    static func openerProof(_ cards: [Card]) -> [Card]? {
        guard qualifies(cards) else { return nil }
        let byRank = Dictionary(grouping: cards, by: { $0.rank })
        let jacksOrBetterPair = byRank
            .filter { $0.value.count >= 2 && $0.key.rawValue >= Rank.jack.rawValue }
            .max { $0.key < $1.key }
        if let pair = jacksOrBetterPair {
            return sorted(Array(pair.value.prefix(2)))
        }
        // Qualifies by a higher category that isn't a jacks-or-better pair
        // (a straight, a flush, low trips, …): the evaluated five cards prove it.
        return HandEvaluator.evaluate(cards).cards
    }
}
