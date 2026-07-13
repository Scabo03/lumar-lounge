// OmahaSessionDriver.swift
// =====================================================================
// The Omaha Pot Limit session driver: the orchestrator that turns single hands
// (GameEngine's `OmahaHand`) into a SESSION — a run of hands at one table by the
// same players, with chips carried across hands, blinds, four community streets,
// busts, dead-button rotation, players joining/leaving between hands, and the
// hands-count STAKE ESCALATION that accelerates a long session (D-064).
//
// It is a pure CLIENT of GameEngine: it never modifies the engine. It creates an
// `OmahaHand`, drives it by reading `legalActions()` and calling `apply(_:)`, and
// reads the `OmahaResult`. Bots and humans answer through the same uniform
// `OmahaActionProvider`. It reuses the Texas/Draw driver's PROVEN SHAPE (ring, dead
// button, event fan-out, between-hand structural changes, D-047 seed policy) without
// sharing their types — Texas and Draw are left untouched (D-042).
//
// GameWorld only.

import Foundation
import GameEngine

/// Drives a multi-hand Omaha Pot Limit session at a single table.
public final class OmahaSessionDriver {

    // MARK: Fixed configuration

    public let capacity: Int
    /// The BASE blinds. The stake escalation ratchets these up over played hands.
    public let smallBlind: Int
    public let bigBlind: Int
    /// The session-acceleration schedule (D-064): hands-count-keyed blind escalation.
    public let escalation: StakeEscalation

    /// The base seed. When set (tests), each hand derives a DETERMINISTIC per-hand
    /// seed from it. When `nil` (production), each hand draws a FRESH RANDOM seed from
    /// the system RNG, so no two hands — and no two sessions — ever repeat (D-047).
    /// The engine stays deterministic given whatever seed it gets.
    private let baseSeed: UInt64?

    // MARK: Mutable table state

    private var positions: [OmahaSessionPlayer?]
    private var providers: [Int: OmahaActionProvider]
    public private(set) var buttonPosition: Int
    /// Number of hands actually played so far — the escalation trigger (D-064).
    public private(set) var handNumber: Int
    /// The escalation level in force at the last hand (to detect a level-up).
    private var lastEscalationLevel = 0
    public private(set) var isHandInProgress: Bool = false
    public private(set) var hasEnded: Bool = false

    // MARK: Event stream

    private let hub = OmahaEventHub()
    private var sessionAnnounced = false
    private var pendingStructuralEvents: [OmahaEventPayload] = []

    // MARK: - Init

    /// - Parameter seed: base seed for DETERMINISTIC play (tests inject a fixed
    ///   value). Pass `nil` (production default) to draw a fresh random seed for every
    ///   hand — always different cards (D-047).
    public init(capacity: Int,
                seats: [OmahaSeatAssignment],
                buttonPosition: Int,
                smallBlind: Int,
                bigBlind: Int,
                seed: UInt64? = nil,
                escalation: StakeEscalation = .none) {
        precondition((2...9).contains(capacity), "An Omaha table seats 2–9.")
        precondition((0..<capacity).contains(buttonPosition), "Button position out of range.")
        precondition(smallBlind > 0 && bigBlind >= smallBlind, "Invalid blinds.")

        var ring: [OmahaSessionPlayer?] = Array(repeating: nil, count: capacity)
        var providerMap: [Int: OmahaActionProvider] = [:]
        for seat in seats {
            precondition((0..<capacity).contains(seat.position), "Seat position out of range.")
            precondition(ring[seat.position] == nil, "Two players in one seat.")
            precondition(providerMap[seat.playerID] == nil, "Duplicate player id.")
            precondition(seat.chips > 0, "A seated player needs positive chips.")
            ring[seat.position] = OmahaSessionPlayer(id: seat.playerID, chips: seat.chips,
                                                     status: .active, position: seat.position)
            providerMap[seat.playerID] = seat.provider
        }

        self.capacity = capacity
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.escalation = escalation
        self.baseSeed = seed
        self.positions = ring
        self.providers = providerMap
        self.buttonPosition = buttonPosition
        self.handNumber = 0
    }

    // MARK: - Queries

    public var players: [OmahaSessionPlayer] {
        positions.compactMap { $0 }.sorted { $0.position < $1.position }
    }
    public func player(_ id: Int) -> OmahaSessionPlayer? {
        positions.compactMap { $0 }.first { $0.id == id }
    }
    public func chips(of id: Int) -> Int? { player(id)?.chips }
    public var eligiblePlayerCount: Int {
        positions.compactMap { $0 }.reduce(0) { $0 + ($1.chips > 0 ? 1 : 0) }
    }
    public var canDealNextHand: Bool { eligiblePlayerCount >= 2 && !isHandInProgress && !hasEnded }

    /// The (possibly escalated) blinds that the NEXT hand will be played at (D-064).
    public var currentBlinds: (small: Int, big: Int) {
        escalation.blinds(baseSmall: smallBlind, baseBig: bigBlind, afterPlayedHands: handNumber)
    }

    // MARK: - Event subscription

    public func events(as viewer: EventViewer = .spectator) async -> AsyncStream<OmahaSessionEvent> {
        await hub.subscribe(as: viewer)
    }

    private func emit(_ payload: OmahaEventPayload, to audience: EventAudience = .everyone) async {
        await hub.emit(payload, audience: audience)
    }

    // MARK: - Structural changes (between hands only)

    public func addPlayer(id: Int, chips: Int, at position: Int, provider: OmahaActionProvider) throws {
        guard !isHandInProgress else { throw OmahaSessionError.handInProgress }
        guard (0..<capacity).contains(position) else { throw OmahaSessionError.positionOutOfRange(position) }
        guard positions[position] == nil else { throw OmahaSessionError.positionOccupied(position) }
        guard player(id) == nil, providers[id] == nil else { throw OmahaSessionError.duplicatePlayerID(id) }
        guard chips > 0 else { throw OmahaSessionError.nonPositiveChips }
        positions[position] = OmahaSessionPlayer(id: id, chips: chips, status: .active, position: position)
        providers[id] = provider
        pendingStructuralEvents.append(.playerJoined(playerID: id, position: position, chips: chips))
    }

    public func removePlayer(id: Int) throws {
        guard !isHandInProgress else { throw OmahaSessionError.handInProgress }
        guard let seated = player(id) else { throw OmahaSessionError.unknownPlayer(id) }
        positions[seated.position] = nil
        providers[id] = nil
        pendingStructuralEvents.append(.playerLeft(playerID: id))
    }

    public func endSession(reason: OmahaSessionEndReason = .stopped) async {
        guard !hasEnded else { return }
        hasEnded = true
        await announceSessionIfNeeded()
        await flushPendingStructuralEvents()
        await emit(.sessionEnded(reason: reason))
        await hub.finishAll()
    }

    // MARK: - Playing one hand

    /// Plays exactly one hand to completion and returns its outcome.
    @discardableResult
    public func playHand() async throws -> OmahaHandOutcome {
        guard !hasEnded else { throw OmahaSessionError.sessionEnded }
        guard !isHandInProgress else { throw OmahaSessionError.handInProgress }
        let participants = eligibleParticipants()
        guard participants.count >= 2 else { throw OmahaSessionError.notEnoughPlayers }

        isHandInProgress = true
        defer { isHandInProgress = false }

        await announceSessionIfNeeded()
        await flushPendingStructuralEvents()

        // Stake escalation for THIS hand, keyed on played hands (D-064).
        let level = escalation.level(afterPlayedHands: handNumber)
        let (sb, bb) = escalation.blinds(baseSmall: smallBlind, baseBig: bigBlind, afterPlayedHands: handNumber)

        let engineSeats = participants.map { OmahaSeat(id: $0.id, stack: $0.chips) }
        let buttonID = engineButtonPlayerID()
        let engineButtonIndex = participants.firstIndex { $0.id == buttonID }!
        let n = participants.count
        let sbIndex = n == 2 ? engineButtonIndex : (engineButtonIndex + 1) % n
        let bbIndex = (sbIndex + 1) % n

        var hand = OmahaHand(seats: engineSeats, buttonIndex: engineButtonIndex,
                             smallBlind: sb, bigBlind: bb, seed: handSeed(handNumber))

        // Announce: hand began, (level-up cue,) blinds posted, cards dealt.
        await emit(.handBegan(
            handNumber: handNumber, buttonPosition: buttonPosition, buttonSeatID: buttonID,
            smallBlindSeatID: participants[sbIndex].id, bigBlindSeatID: participants[bbIndex].id,
            smallBlind: sb, bigBlind: bb,
            seats: participants.map { OmahaSeatSnapshot(seatID: $0.id, position: $0.position, chips: $0.chips) }))
        if level > lastEscalationLevel {
            await emit(.stakesEscalated(smallBlind: sb, bigBlind: bb, level: level))
            lastEscalationLevel = level
        }
        await emit(.blindPosted(seatID: participants[sbIndex].id, blind: .small,
                                amount: hand.seats[sbIndex].streetBet, isAllIn: hand.seats[sbIndex].isAllIn))
        await emit(.blindPosted(seatID: participants[bbIndex].id, blind: .big,
                                amount: hand.seats[bbIndex].streetBet, isAllIn: hand.seats[bbIndex].isAllIn))
        for i in participants.indices {
            let seat = hand.seats[i]
            await emit(.holeCardsDealt(seatID: seat.id))
            await emit(.privateHoleCards(seatID: seat.id, cards: seat.holeCards), to: .player(seat.id))
        }

        // Drive the hand: betting actions across the four streets, narrated.
        var announcedBoard = 0
        while !hand.isComplete {
            guard let ctx = OmahaBotContext(actingIn: hand) else { break }
            let actingID = ctx.heroSeatID
            let index = hand.seats.firstIndex { $0.id == actingID }!
            let stackBefore = hand.seats[index].stack
            let currentBetBefore = hand.currentBet

            let requested = await providers[actingID]?.provideAction(for: ctx) ?? .fold
            let action = legalizeAction(requested, ctx.legal)
            try hand.apply(action)

            let after = hand.seats.first { $0.id == actingID }!
            let committed = stackBefore - after.stack
            await emit(.playerActed(seatID: actingID,
                                    action: classify(action, toStreetBet: after.streetBet,
                                                     currentBetBefore: currentBetBefore,
                                                     committed: committed, isAllIn: after.stack == 0)))
            await announceStreets(&announcedBoard, board: hand.board)
        }
        await announceStreets(&announcedBoard, board: hand.board)   // any streets opened during runout

        let result = hand.result!
        return await finish(result, participants: participants,
                            smallBlind: sb, bigBlind: bb, escalationLevel: level)
    }

    /// Convenience loop: plays hands while it can and `shouldContinue` allows.
    @discardableResult
    public func run(maxHands: Int = .max,
                    continuing shouldContinue: (OmahaHandOutcome) -> Bool = { _ in true }) async throws -> [OmahaHandOutcome] {
        var outcomes: [OmahaHandOutcome] = []
        while outcomes.count < maxHands && canDealNextHand {
            let outcome = try await playHand()
            outcomes.append(outcome)
            if !shouldContinue(outcome) { break }
        }
        return outcomes
    }

    // MARK: - Finishing a hand

    private func finish(_ result: OmahaResult, participants: [OmahaSessionPlayer],
                        smallBlind sb: Int, bigBlind bb: Int, escalationLevel level: Int) async -> OmahaHandOutcome {
        var busted: [Int] = []
        for participant in participants {
            let finalStack = result.finalStacks[participant.id] ?? participant.chips
            setChips(participant.id, to: finalStack)
            if finalStack == 0 { busted.append(participant.id) }
        }
        let chipsByPlayer = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.chips) })

        if result.wentToShowdown {
            for participant in participants where result.shownHands[participant.id] != nil {
                let cards = result.shownHands[participant.id]!
                let rank = result.bestHands[participant.id]!
                await emit(.handShown(seatID: participant.id, holeCards: cards,
                                      category: rank.category, bestFive: rank.cards))
            }
        }
        for (potIndex, pot) in result.pots.enumerated() {
            await emit(.potAwarded(potIndex: potIndex, amount: pot.amount,
                                   winnerSeatIDs: potWinners(pot, result)))
        }
        await emit(.handEnded(handNumber: handNumber, wentToShowdown: result.wentToShowdown,
                              board: result.board, payouts: result.payouts, chips: chipsByPlayer))
        for id in busted.sorted() { await emit(.playerBusted(playerID: id)) }

        let outcome = OmahaHandOutcome(handNumber: handNumber, buttonPosition: buttonPosition,
                                       participantIDs: participants.map { $0.id }, result: result,
                                       smallBlind: sb, bigBlind: bb, escalationLevel: level,
                                       bustedThisHand: busted.sorted(), chipsByPlayer: chipsByPlayer)
        handNumber += 1
        buttonPosition = (buttonPosition + 1) % capacity   // dead button, advance one
        return outcome
    }

    // MARK: - Table ↔ engine mapping

    private func eligibleParticipants() -> [OmahaSessionPlayer] {
        positions.compactMap { $0 }.filter { $0.chips > 0 }.sorted { $0.position < $1.position }
    }

    /// The player id the engine should treat as the button: dead-button rule — first
    /// eligible player scanning counter-clockwise from the physical button (D-012).
    private func engineButtonPlayerID() -> Int {
        for step in 0..<capacity {
            let position = (buttonPosition - step + capacity) % capacity
            if let seated = positions[position], seated.chips > 0 { return seated.id }
        }
        preconditionFailure("No eligible player for the button.")
    }

    /// The winners of a pot for narration: eligible seats reduced to the best
    /// evaluated CONSTRAINED hand at showdown (fold-out → the single eligible seat).
    private func potWinners(_ pot: Pot, _ result: OmahaResult) -> [Int] {
        let eligible = pot.eligibleSeatIDs
        if result.bestHands.isEmpty { return eligible }
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

    private func announceStreets(_ announced: inout Int, board: [Card]) async {
        if board.count >= 3 && announced < 3 {
            await emit(.streetOpened(street: .flop, communityCards: Array(board[0..<3])))
            announced = 3
        }
        if board.count >= 4 && announced < 4 {
            await emit(.streetOpened(street: .turn, communityCards: [board[3]]))
            announced = 4
        }
        if board.count >= 5 && announced < 5 {
            await emit(.streetOpened(street: .river, communityCards: [board[4]]))
            announced = 5
        }
    }

    private func setChips(_ id: Int, to chips: Int) {
        guard let index = positions.firstIndex(where: { $0?.id == id }) else { return }
        positions[index]?.chips = chips
        positions[index]?.status = chips == 0 ? .bustedOut : .active
    }

    /// Defensively coerce a requested action to a legal one (fallback check/fold),
    /// so the driver stays total even with a misbehaving provider (D-013).
    private func legalizeAction(_ action: OmahaAction, _ legal: OmahaLegalActions) -> OmahaAction {
        switch action {
        case .fold:  return legal.canFold ? .fold : .fold
        case .check: return legal.canCheck ? .check : (legal.canCall ? .call : .fold)
        case .call:  return legal.canCall ? .call : (legal.canCheck ? .check : .fold)
        case .allIn: return legal.canAllIn ? .allIn : (legal.canCheck ? .check : .fold)
        case .bet(let to):
            guard legal.canBet else { return legal.canCheck ? .check : .fold }
            return .bet(min(max(to, legal.minBetTo), legal.maxBetTo))
        case .raise(let to):
            guard legal.canRaise else { return legal.canCall ? .call : (legal.canCheck ? .check : .fold) }
            return .raise(min(max(to, legal.minRaiseTo), legal.maxRaiseTo))
        }
    }

    private func classify(_ action: OmahaAction, toStreetBet: Int, currentBetBefore: Int,
                          committed: Int, isAllIn: Bool) -> OmahaActedAction {
        switch action {
        case .fold:  return .folded
        case .check: return .checked
        default:
            if toStreetBet <= currentBetBefore {
                return .called(amount: committed, isAllIn: isAllIn)     // matched or short all-in call
            } else if currentBetBefore == 0 {
                return .bet(to: toStreetBet, amount: committed, isAllIn: isAllIn)
            } else {
                return .raised(to: toStreetBet, amount: committed, isAllIn: isAllIn)
            }
        }
    }

    /// The seed for a hand. With a base seed (tests) it is a DETERMINISTIC function of
    /// the base seed and the hand number; without one (production) it is a FRESH
    /// RANDOM draw from the system RNG, so no two hands repeat (D-047).
    private func handSeed(_ number: Int) -> UInt64 {
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
            seats: players.map { OmahaSeatSnapshot(seatID: $0.id, position: $0.position, chips: $0.chips) },
            smallBlind: smallBlind, bigBlind: bigBlind))
    }

    private func flushPendingStructuralEvents() async {
        let pending = pendingStructuralEvents
        pendingStructuralEvents.removeAll()
        for payload in pending { await emit(payload) }
    }
}
