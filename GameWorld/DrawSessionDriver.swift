// DrawSessionDriver.swift
// =====================================================================
// The Five-Card Draw session driver (D-042): the orchestrator that turns single
// deals (GameEngine's `FiveCardDrawHand`) into a SESSION — a run of deals at one
// table by the same players, with chips carried across deals, ante posting, the
// draw exchange, the progressive pot of pass-and-out, busts, dead-button rotation
// and players joining/leaving between deals.
//
// It is a pure CLIENT of GameEngine: it never modifies the engine. It creates a
// `FiveCardDrawHand`, drives it by reading `legalActions()`/`drawOptions()` and
// calling `apply(_:)`/`discard(_:)`, and reads the `DrawResult`. Bots and humans
// answer through the same uniform `DrawActionProvider` (betting AND drawing).
//
// It reuses the Texas driver's PROVEN SHAPE (ring, dead button, event fan-out,
// between-deal structural changes) without sharing its types, because the draw
// rules differ enough (ante, two limit rounds, draw, pass-and-out) that forcing a
// shared abstraction would add rigidity, not value (D-042). The Texas driver is
// left untouched.
//
// Progressive pot (D-040): when a deal is passed in (nobody opened), its antes are
// kept as `carriedPot` and fed into the next deal; the button does NOT rotate on a
// passed deal, and the played-hand counter does not advance.
//
// GameWorld only.

import Foundation
import GameEngine

/// Drives a multi-deal Five-Card Draw session at a single table.
public final class DrawSessionDriver {

    // MARK: Fixed configuration

    public let capacity: Int
    public let ante: Int
    public let smallBet: Int
    public let bigBet: Int
    /// The base seed. When set (tests), each deal derives a DETERMINISTIC per-deal
    /// seed from it. When `nil` (production), each deal draws a FRESH RANDOM seed
    /// from the system RNG, so every deal — and every session — plays differently
    /// (D-047). The engine stays deterministic given whatever seed it gets.
    private let baseSeed: UInt64?

    // MARK: Mutable table state

    private var positions: [DrawSessionPlayer?]
    private var providers: [Int: DrawActionProvider]
    public private(set) var buttonPosition: Int
    /// Number of deals actually PLAYED so far (passed-in deals don't advance this).
    public private(set) var handNumber: Int
    /// A monotonic counter over ALL deal attempts (played or passed), used to give
    /// each deal — including a re-dealt passed one — a fresh shuffle seed.
    private var dealIndex: Int = 0
    /// The progressive pot carried into the next deal (grows on pass-and-out, D-040).
    public private(set) var carriedPot: Int = 0
    /// Consecutive deals passed in so far (resets to 0 when one is played).
    public private(set) var consecutivePassed: Int = 0
    public private(set) var isDealInProgress: Bool = false
    public private(set) var hasEnded: Bool = false

    // MARK: Event stream

    private let hub = DrawEventHub()
    private var sessionAnnounced = false
    private var pendingStructuralEvents: [DrawEventPayload] = []

    // MARK: - Init

    /// - Parameter seed: base seed for DETERMINISTIC play (tests inject a fixed
    ///   value). Pass `nil` (the default, used in production) to draw a fresh random
    ///   seed for every deal from the system RNG — always different cards (D-047).
    public init(capacity: Int,
                seats: [DrawSeatAssignment],
                buttonPosition: Int,
                ante: Int,
                smallBet: Int,
                bigBet: Int,
                seed: UInt64? = nil) {
        precondition((2...7).contains(capacity), "A draw table seats 2–7.")
        precondition((0..<capacity).contains(buttonPosition), "Button position out of range.")
        precondition(ante > 0 && smallBet > 0 && bigBet >= smallBet, "Invalid ante/bet sizes.")

        var ring: [DrawSessionPlayer?] = Array(repeating: nil, count: capacity)
        var providerMap: [Int: DrawActionProvider] = [:]
        for seat in seats {
            precondition((0..<capacity).contains(seat.position), "Seat position out of range.")
            precondition(ring[seat.position] == nil, "Two players in one seat.")
            precondition(providerMap[seat.playerID] == nil, "Duplicate player id.")
            precondition(seat.chips > 0, "A seated player needs positive chips.")
            ring[seat.position] = DrawSessionPlayer(id: seat.playerID, chips: seat.chips,
                                                    status: .active, position: seat.position)
            providerMap[seat.playerID] = seat.provider
        }

        self.capacity = capacity
        self.ante = ante
        self.smallBet = smallBet
        self.bigBet = bigBet
        self.baseSeed = seed
        self.positions = ring
        self.providers = providerMap
        self.buttonPosition = buttonPosition
        self.handNumber = 0
    }

    // MARK: - Queries

    public var players: [DrawSessionPlayer] {
        positions.compactMap { $0 }.sorted { $0.position < $1.position }
    }
    public func player(_ id: Int) -> DrawSessionPlayer? {
        positions.compactMap { $0 }.first { $0.id == id }
    }
    public func chips(of id: Int) -> Int? { player(id)?.chips }
    public var eligiblePlayerCount: Int {
        positions.compactMap { $0 }.reduce(0) { $0 + ($1.chips > 0 ? 1 : 0) }
    }
    public var canDealNextHand: Bool { eligiblePlayerCount >= 2 && !isDealInProgress && !hasEnded }

    // MARK: - Event subscription

    public func events(as viewer: EventViewer = .spectator) async -> AsyncStream<DrawSessionEvent> {
        await hub.subscribe(as: viewer)
    }

    private func emit(_ payload: DrawEventPayload, to audience: EventAudience = .everyone) async {
        await hub.emit(payload, audience: audience)
    }

    // MARK: - Structural changes (between deals only)

    public func addPlayer(id: Int, chips: Int, at position: Int, provider: DrawActionProvider) throws {
        guard !isDealInProgress else { throw DrawSessionError.handInProgress }
        guard (0..<capacity).contains(position) else { throw DrawSessionError.positionOutOfRange(position) }
        guard positions[position] == nil else { throw DrawSessionError.positionOccupied(position) }
        guard player(id) == nil, providers[id] == nil else { throw DrawSessionError.duplicatePlayerID(id) }
        guard chips > 0 else { throw DrawSessionError.nonPositiveChips }
        positions[position] = DrawSessionPlayer(id: id, chips: chips, status: .active, position: position)
        providers[id] = provider
        pendingStructuralEvents.append(.playerJoined(playerID: id, position: position, chips: chips))
    }

    public func removePlayer(id: Int) throws {
        guard !isDealInProgress else { throw DrawSessionError.handInProgress }
        guard let seated = player(id) else { throw DrawSessionError.unknownPlayer(id) }
        positions[seated.position] = nil
        providers[id] = nil
        pendingStructuralEvents.append(.playerLeft(playerID: id))
    }

    public func endSession(reason: DrawSessionEndReason = .stopped) async {
        guard !hasEnded else { return }
        hasEnded = true
        await announceSessionIfNeeded()
        await flushPendingStructuralEvents()
        await emit(.sessionEnded(reason: reason))
        await hub.finishAll()
    }

    // MARK: - Playing one deal

    /// Plays exactly one deal to completion and returns its outcome. A deal may be
    /// PASSED IN (nobody opened): then its antes carry into `carriedPot`, the button
    /// does not rotate, and `wasPlayed` is false. Otherwise chips are updated, busts
    /// marked, the progressive pot cleared, and the button advances one position.
    @discardableResult
    public func playHand() async throws -> DrawHandOutcome {
        guard !hasEnded else { throw DrawSessionError.sessionEnded }
        guard !isDealInProgress else { throw DrawSessionError.handInProgress }
        let participants = eligibleParticipants()
        guard participants.count >= 2 else { throw DrawSessionError.notEnoughPlayers }

        isDealInProgress = true
        defer { isDealInProgress = false }

        await announceSessionIfNeeded()
        await flushPendingStructuralEvents()

        let engineSeats = participants.map { DrawSeat(id: $0.id, stack: $0.chips) }
        let buttonID = engineButtonPlayerID()
        let engineButtonIndex = participants.firstIndex { $0.id == buttonID }!

        var hand = FiveCardDrawHand(seats: engineSeats,
                                    buttonIndex: engineButtonIndex,
                                    ante: ante, smallBet: smallBet, bigBet: bigBet,
                                    seed: dealSeed(dealIndex), carryPot: carriedPot)
        dealIndex += 1

        // Deal announced: hand began, antes posted, cards dealt (public + private).
        await emit(.handBegan(
            handNumber: handNumber, buttonPosition: buttonPosition, buttonSeatID: buttonID,
            ante: ante, smallBet: smallBet, bigBet: bigBet, carriedPot: carriedPot,
            seats: participants.map { DrawSeatSnapshot(seatID: $0.id, position: $0.position, chips: $0.chips) }))
        for i in participants.indices {
            let seat = hand.seats[i]   // engineSeats mirror participants order
            await emit(.antePosted(seatID: seat.id, amount: seat.totalBet, isAllIn: seat.isAllIn))
        }
        for i in participants.indices {
            let seat = hand.seats[i]
            await emit(.cardsDealt(seatID: seat.id))
            await emit(.privateCards(seatID: seat.id, cards: seat.cards), to: .player(seat.id))
        }

        // Drive the deal: betting actions and the draw exchange, narrated.
        var phaseSeen: DrawPhase = hand.phase
        while !hand.isComplete {
            if let ctx = DrawBotContext(actingIn: hand) {
                let actingID = ctx.heroSeatID
                let index = hand.seats.firstIndex { $0.id == actingID }!
                let stackBefore = hand.seats[index].stack
                let currentBetBefore = hand.currentBet
                let hadOpeners = ctx.legal.hasOpeners
                let round: DrawRound = hand.phase == .secondBet ? .second : .first

                let requested = await providers[actingID]?.provideAction(for: ctx) ?? .fold
                let action = legalizeAction(requested, ctx.legal)
                let wasOpeningBet = (action == .bet && currentBetBefore == 0)
                try hand.apply(action)

                let stackAfter = hand.seats.first { $0.id == actingID }!.stack
                let committed = stackBefore - stackAfter
                if wasOpeningBet { await emit(.potOpened(seatID: actingID, hasOpeners: hadOpeners)) }
                await emit(.playerActed(seatID: actingID,
                                        action: classify(action, committed: committed, isAllIn: stackAfter == 0),
                                        round: round))
            } else if let options = hand.drawOptions() {
                if phaseSeen != .draw { await emit(.drawPhaseBegan); phaseSeen = .draw }
                let ctx = DrawDrawContext(drawingIn: hand)!
                let seatID = options.seatID
                let requested = await providers[seatID]?.provideDiscards(for: ctx) ?? []
                let discards = legalizeDiscards(requested, held: options.cards)
                try hand.discard(discards)
                await emit(.playerDrew(seatID: seatID, discardCount: discards.count))
                let newCards = hand.seats.first { $0.id == seatID }!.cards
                await emit(.privateDrawnCards(seatID: seatID, cards: newCards), to: .player(seatID))
            } else {
                break
            }
            if hand.phase == .secondBet && phaseSeen != .secondBet {
                await emit(.secondBetBegan); phaseSeen = .secondBet
            }
        }

        let result = hand.result!
        return await finish(result, participants: participants)
    }

    /// Convenience loop: plays deals while it can and `shouldContinue` allows.
    @discardableResult
    public func run(maxHands: Int = .max,
                    continuing shouldContinue: (DrawHandOutcome) -> Bool = { _ in true }) async throws -> [DrawHandOutcome] {
        var outcomes: [DrawHandOutcome] = []
        while outcomes.count < maxHands && canDealNextHand {
            let outcome = try await playHand()
            outcomes.append(outcome)
            if !shouldContinue(outcome) { break }
        }
        return outcomes
    }

    // MARK: - Finishing a deal

    private func finish(_ result: DrawResult, participants: [DrawSessionPlayer]) async -> DrawHandOutcome {
        // Update chips for every participant, detect busts.
        var busted: [Int] = []
        for participant in participants {
            let finalStack = result.finalStacks[participant.id] ?? participant.chips
            setChips(participant.id, to: finalStack)
            if finalStack == 0 { busted.append(participant.id) }
        }
        let chipsByPlayer = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.chips) })

        switch result.outcome {
        case .passedIn:
            // Progressive pot grows; button and played-hand counter stay put (D-040).
            carriedPot = result.carriedPot
            consecutivePassed += 1
            await emit(.passedIn(carriedPot: carriedPot, consecutivePassed: consecutivePassed))
            await emit(.handEnded(handNumber: handNumber, outcome: .passedIn, chips: chipsByPlayer))
            for id in busted.sorted() { await emit(.playerBusted(playerID: id)) }
            return DrawHandOutcome(handNumber: handNumber, buttonPosition: buttonPosition,
                                   participantIDs: participants.map { $0.id }, result: result,
                                   wasPlayed: false, carriedPot: carriedPot,
                                   consecutivePassed: consecutivePassed,
                                   bustedThisHand: busted.sorted(), chipsByPlayer: chipsByPlayer)

        case .showdown, .foldOut:
            if result.wentToShowdown {
                for participant in participants where result.revealedHands[participant.id] != nil {
                    let cards = result.revealedHands[participant.id]!
                    let rank = result.bestHands[participant.id]!
                    await emit(.handShown(seatID: participant.id, cards: cards,
                                          category: rank.category, bestFive: rank.cards))
                }
            }
            if result.openerDisqualified, let disqualified = result.openerSeatID {
                await emit(.openersDisqualified(seatID: disqualified))
            }
            for (potIndex, pot) in result.pots.enumerated() {
                await emit(.potAwarded(potIndex: potIndex, amount: pot.amount,
                                       winnerSeatIDs: potWinners(pot, result)))
            }
            await emit(.handEnded(handNumber: handNumber, outcome: result.outcome, chips: chipsByPlayer))
            for id in busted.sorted() { await emit(.playerBusted(playerID: id)) }

            let playedNumber = handNumber
            let outcome = DrawHandOutcome(handNumber: playedNumber, buttonPosition: buttonPosition,
                                          participantIDs: participants.map { $0.id }, result: result,
                                          wasPlayed: true, carriedPot: 0, consecutivePassed: 0,
                                          bustedThisHand: busted.sorted(), chipsByPlayer: chipsByPlayer)
            carriedPot = 0
            consecutivePassed = 0
            handNumber += 1
            buttonPosition = (buttonPosition + 1) % capacity   // dead button, advance one
            return outcome
        }
    }

    // MARK: - Table ↔ engine mapping

    private func eligibleParticipants() -> [DrawSessionPlayer] {
        positions.compactMap { $0 }.filter { $0.chips > 0 }.sorted { $0.position < $1.position }
    }

    /// The player id the engine should treat as the button: dead-button rule —
    /// first eligible player scanning counter-clockwise from the physical button.
    private func engineButtonPlayerID() -> Int {
        for step in 0..<capacity {
            let position = (buttonPosition - step + capacity) % capacity
            if let seated = positions[position], seated.chips > 0 { return seated.id }
        }
        preconditionFailure("No eligible player for the button.")
    }

    /// The winners of a pot for narration: the eligible seats (minus a disqualified
    /// opener), reduced to the best evaluated hand at showdown. Mirrors the engine.
    private func potWinners(_ pot: Pot, _ result: DrawResult) -> [Int] {
        let disqualified: Set<Int> = result.openerDisqualified
            ? Set(result.openerSeatID.map { [$0] } ?? []) : []
        let eligible = pot.eligibleSeatIDs.filter { !disqualified.contains($0) }
        if result.bestHands.isEmpty { return eligible }   // fold-out
        var best: HandRank?
        var winners: [Int] = []
        for id in eligible {
            guard let rank = result.bestHands[id] else { continue }
            if best == nil || rank > best! { best = rank; winners = [id] }
            else if rank == best! { winners.append(id) }
        }
        return winners.isEmpty ? eligible : winners
    }

    // MARK: - Helpers

    private func setChips(_ id: Int, to chips: Int) {
        guard let index = positions.firstIndex(where: { $0?.id == id }) else { return }
        positions[index]?.chips = chips
        positions[index]?.status = chips == 0 ? .bustedOut : .active
    }

    private func legalizeAction(_ action: DrawAction, _ legal: DrawLegalActions) -> DrawAction {
        isPermitted(action, legal) ? action : (legal.canCheck ? .check : .fold)
    }

    private func isPermitted(_ action: DrawAction, _ legal: DrawLegalActions) -> Bool {
        switch action {
        case .fold:  return legal.canFold
        case .check: return legal.canCheck
        case .call:  return legal.canCall
        case .bet:   return legal.canBet
        case .raise: return legal.canRaise
        }
    }

    /// Coerces requested discards to a legal exchange: distinct held cards, at most
    /// four, in the requested order.
    private func legalizeDiscards(_ cards: [Card], held: [Card]) -> [Card] {
        var remaining = held
        var result: [Card] = []
        for card in cards where result.count < 4 {
            if let index = remaining.firstIndex(of: card) {
                remaining.remove(at: index)
                result.append(card)
            }
        }
        return result
    }

    private func classify(_ action: DrawAction, committed: Int, isAllIn: Bool) -> DrawActedAction {
        switch action {
        case .fold:  return .folded
        case .check: return .checked
        case .call:  return .called(amount: committed, isAllIn: isAllIn)
        case .bet:   return .bet(amount: committed, isAllIn: isAllIn)
        case .raise: return .raised(amount: committed, isAllIn: isAllIn)
        }
    }

    /// The seed for a deal. With a base seed (tests) it is a DETERMINISTIC function
    /// of the base seed and the deal index; without one (production) it is a FRESH
    /// RANDOM draw from the system RNG, so no two deals ever repeat (D-047).
    private func dealSeed(_ number: Int) -> UInt64 {
        guard let baseSeed else { return UInt64.random(in: .min ... .max) }
        var z = baseSeed &+ (UInt64(bitPattern: Int64(number)) &* 0x9E37_79B9_7F4A_7C15)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    private func announceSessionIfNeeded() async {
        guard !sessionAnnounced else { return }
        sessionAnnounced = true
        await emit(.sessionBegan(
            seats: players.map { DrawSeatSnapshot(seatID: $0.id, position: $0.position, chips: $0.chips) },
            ante: ante, smallBet: smallBet, bigBet: bigBet))
    }

    private func flushPendingStructuralEvents() async {
        let pending = pendingStructuralEvents
        pendingStructuralEvents.removeAll()
        for payload in pending { await emit(payload) }
    }
}
