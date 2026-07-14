// StudSessionDriver.swift
// =====================================================================
// The Seven-Card Stud Pot Limit session driver: the orchestrator that turns single
// hands (GameEngine's `StudHand`) into a SESSION — a run of hands at one table by the
// same players, with chips carried across hands, the ante + bring-in, five streets of
// up/down cards, busts, players joining/leaving between hands, and the ClockTower's
// HOUSE PRIZE (D-078) that rewards the player for each hand they win.
//
// It is a pure CLIENT of GameEngine: it never modifies the engine. It creates a
// `StudHand`, drives it by reading `legalActions()` and calling `apply(_:)`, and reads
// the `StudResult`. Bots and humans answer through the same uniform `StudActionProvider`.
// It reuses the proven driver SHAPE (ring, event fan-out, between-hand structural
// changes, D-047 seed policy) without sharing the other games' types (D-077). Stud has
// NO button — dealing order is a fixed seat order over a randomly shuffled deck.
//
// GameWorld only.

import Foundation
import GameEngine

/// Drives a multi-hand Seven-Card Stud Pot Limit session at a single table.
public final class StudSessionDriver {

    // MARK: Fixed configuration

    public let capacity: Int
    /// The BASE stakes. The stake escalation ratchets these up over played hands (D-064).
    public let ante: Int
    public let bringIn: Int
    public let bet: Int
    public let escalation: StakeEscalation
    /// The flat prize the House adds when the prize recipient wins a hand (D-078). 0 off.
    public let housePrize: Int
    /// The player id the house prize is paid to (the human). `nil` disables the prize.
    public let prizeRecipientID: Int?

    /// The base seed. When set (tests) each hand derives a DETERMINISTIC per-hand seed;
    /// when `nil` (production) each hand draws a FRESH RANDOM seed, so no two hands — and
    /// no two sessions — ever repeat (D-047). The engine stays deterministic given a seed.
    private let baseSeed: UInt64?

    // MARK: Mutable table state

    private var positions: [StudSessionPlayer?]
    private var providers: [Int: StudActionProvider]
    /// Number of hands actually played so far — the escalation trigger (D-064).
    public private(set) var handNumber: Int
    private var lastEscalationLevel = 0
    public private(set) var isHandInProgress: Bool = false
    public private(set) var hasEnded: Bool = false

    // MARK: Event stream

    private let hub = StudEventHub()
    private var sessionAnnounced = false
    private var pendingStructuralEvents: [StudEventPayload] = []

    // MARK: - Init

    public init(capacity: Int,
                seats: [StudSeatAssignment],
                ante: Int,
                bringIn: Int,
                bet: Int,
                housePrize: Int = 0,
                prizeRecipientID: Int? = nil,
                seed: UInt64? = nil,
                escalation: StakeEscalation = .none) {
        precondition((2...8).contains(capacity), "A Stud table seats 2–8.")
        precondition(ante >= 0 && bringIn > 0 && bet > 0 && bringIn <= bet, "Invalid ante/bring-in/bet.")

        var ring: [StudSessionPlayer?] = Array(repeating: nil, count: capacity)
        var providerMap: [Int: StudActionProvider] = [:]
        for seat in seats {
            precondition((0..<capacity).contains(seat.position), "Seat position out of range.")
            precondition(ring[seat.position] == nil, "Two players in one seat.")
            precondition(providerMap[seat.playerID] == nil, "Duplicate player id.")
            precondition(seat.chips > 0, "A seated player needs positive chips.")
            ring[seat.position] = StudSessionPlayer(id: seat.playerID, chips: seat.chips,
                                                    status: .active, position: seat.position)
            providerMap[seat.playerID] = seat.provider
        }

        self.capacity = capacity
        self.ante = ante
        self.bringIn = bringIn
        self.bet = bet
        self.housePrize = housePrize
        self.prizeRecipientID = prizeRecipientID
        self.escalation = escalation
        self.baseSeed = seed
        self.positions = ring
        self.providers = providerMap
        self.handNumber = 0
    }

    // MARK: - Queries

    public var players: [StudSessionPlayer] {
        positions.compactMap { $0 }.sorted { $0.position < $1.position }
    }
    public func player(_ id: Int) -> StudSessionPlayer? {
        positions.compactMap { $0 }.first { $0.id == id }
    }
    public func chips(of id: Int) -> Int? { player(id)?.chips }
    public var eligiblePlayerCount: Int {
        positions.compactMap { $0 }.reduce(0) { $0 + ($1.chips > 0 ? 1 : 0) }
    }
    public var canDealNextHand: Bool { eligiblePlayerCount >= 2 && !isHandInProgress && !hasEnded }

    /// The (possibly escalated) stakes the NEXT hand will be played at (D-064).
    public var currentStakes: (ante: Int, bringIn: Int, bet: Int) {
        stakes(afterPlayedHands: handNumber)
    }

    private func stakes(afterPlayedHands hands: Int) -> (ante: Int, bringIn: Int, bet: Int) {
        let m = escalation.multiplier(afterPlayedHands: hands)
        let a = max(0, Int((Double(ante) * m).rounded()))
        let b = max(1, Int((Double(bringIn) * m).rounded()))
        let full = max(b, Int((Double(bet) * m).rounded()))
        return (a, b, full)
    }

    // MARK: - Event subscription

    public func events(as viewer: EventViewer = .spectator) async -> AsyncStream<StudSessionEvent> {
        await hub.subscribe(as: viewer)
    }

    private func emit(_ payload: StudEventPayload, to audience: EventAudience = .everyone) async {
        await hub.emit(payload, audience: audience)
    }

    // MARK: - Structural changes (between hands only)

    public func addPlayer(id: Int, chips: Int, at position: Int, provider: StudActionProvider) throws {
        guard !isHandInProgress else { throw StudSessionError.handInProgress }
        guard (0..<capacity).contains(position) else { throw StudSessionError.positionOutOfRange(position) }
        guard positions[position] == nil else { throw StudSessionError.positionOccupied(position) }
        guard player(id) == nil, providers[id] == nil else { throw StudSessionError.duplicatePlayerID(id) }
        guard chips > 0 else { throw StudSessionError.nonPositiveChips }
        positions[position] = StudSessionPlayer(id: id, chips: chips, status: .active, position: position)
        providers[id] = provider
        pendingStructuralEvents.append(.playerJoined(playerID: id, position: position, chips: chips))
    }

    public func removePlayer(id: Int) throws {
        guard !isHandInProgress else { throw StudSessionError.handInProgress }
        guard let seated = player(id) else { throw StudSessionError.unknownPlayer(id) }
        positions[seated.position] = nil
        providers[id] = nil
        pendingStructuralEvents.append(.playerLeft(playerID: id))
    }

    public func endSession(reason: StudSessionEndReason = .stopped) async {
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
    public func playHand() async throws -> StudHandOutcome {
        guard !hasEnded else { throw StudSessionError.sessionEnded }
        guard !isHandInProgress else { throw StudSessionError.handInProgress }
        let participants = eligibleParticipants()
        guard participants.count >= 2 else { throw StudSessionError.notEnoughPlayers }

        isHandInProgress = true
        defer { isHandInProgress = false }

        await announceSessionIfNeeded()
        await flushPendingStructuralEvents()

        let level = escalation.level(afterPlayedHands: handNumber)
        let (a, bi, b) = stakes(afterPlayedHands: handNumber)

        let engineSeats = participants.map { StudSeat(id: $0.id, stack: $0.chips) }
        var hand = StudHand(seats: engineSeats, ante: a, bringIn: bi, bet: b, seed: handSeed(handNumber))

        // Announce: hand began, (level-up cue,) antes, third-street cards, the bring-in.
        await emit(.handBegan(handNumber: handNumber, ante: a, bringIn: bi, bet: b,
                              seats: participants.map { StudSeatSnapshot(seatID: $0.id, position: $0.position, chips: $0.chips) }))
        for (i, participant) in participants.enumerated() {
            let anteAmount = min(a, participant.chips)
            await emit(.antePosted(seatID: participant.id, amount: anteAmount, isAllIn: hand.seats[i].stack == 0))
        }
        for i in participants.indices {
            let seat = hand.seats[i]
            await emit(.holeCardsDealt(seatID: seat.id))
            await emit(.privateDownCards(seatID: seat.id, cards: seat.holeCards), to: .player(seat.id))
            await emit(.upCardDealt(seatID: seat.id, card: seat.upCards[0], street: .third))
        }
        if let bringInIndex = hand.seats.firstIndex(where: { $0.streetBet > 0 }) {
            let seat = hand.seats[bringInIndex]
            await emit(.bringInPosted(seatID: seat.id, amount: seat.streetBet, isAllIn: seat.stack == 0))
        }

        // Drive the hand: betting across the five streets, narrated with card reveals.
        var announcedStreet = StudStreet.third
        while !hand.isComplete {
            guard let ctx = StudBotContext(actingIn: hand) else { break }
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
            await announceNewStreets(&announcedStreet, hand: hand)
        }
        await announceNewStreets(&announcedStreet, hand: hand)   // any streets opened during runout

        let result = hand.result!
        return await finish(result, participants: participants, ante: a, bringIn: bi, bet: b, escalationLevel: level)
    }

    /// Convenience loop: plays hands while it can and `shouldContinue` allows.
    @discardableResult
    public func run(maxHands: Int = .max,
                    continuing shouldContinue: (StudHandOutcome) -> Bool = { _ in true }) async throws -> [StudHandOutcome] {
        var outcomes: [StudHandOutcome] = []
        while outcomes.count < maxHands && canDealNextHand {
            let outcome = try await playHand()
            outcomes.append(outcome)
            if !shouldContinue(outcome) { break }
        }
        return outcomes
    }

    // MARK: - Finishing a hand

    private func finish(_ result: StudResult, participants: [StudSessionPlayer],
                        ante: Int, bringIn: Int, bet: Int, escalationLevel level: Int) async -> StudHandOutcome {
        var busted: [Int] = []
        for participant in participants {
            let finalStack = result.finalStacks[participant.id] ?? participant.chips
            setChips(participant.id, to: finalStack)
            if finalStack == 0 { busted.append(participant.id) }
        }

        if result.wentToShowdown {
            for participant in participants where result.shownHands[participant.id] != nil {
                let cards = result.shownHands[participant.id]!
                let rank = result.bestHands[participant.id]!
                await emit(.handShown(seatID: participant.id, cards: cards,
                                      category: rank.category, bestFive: rank.cards))
            }
        }
        for (potIndex, pot) in result.pots.enumerated() {
            await emit(.potAwarded(potIndex: potIndex, amount: pot.amount, winnerSeatIDs: potWinners(pot, result)))
        }

        // HOUSE PRIZE (D-078): if the prize recipient (the human) won this hand, the House
        // tops up their pot. Added to their chips AFTER the pot, so `handEnded` reflects it.
        var prizeAwarded = 0
        if let recipient = prizeRecipientID, housePrize > 0,
           (result.payouts[recipient] ?? 0) > 0, let current = chips(of: recipient) {
            prizeAwarded = housePrize
            setChips(recipient, to: current + housePrize)
            await emit(.housePrizeAwarded(playerID: recipient, amount: housePrize))
        }

        let chipsByPlayer = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.chips) })
        await emit(.handEnded(handNumber: handNumber, wentToShowdown: result.wentToShowdown,
                              payouts: result.payouts, chips: chipsByPlayer))
        for id in busted.sorted() { await emit(.playerBusted(playerID: id)) }

        let outcome = StudHandOutcome(handNumber: handNumber, participantIDs: participants.map { $0.id },
                                      result: result, ante: ante, bringIn: bringIn, bet: bet,
                                      escalationLevel: level, housePrizeAwarded: prizeAwarded,
                                      bustedThisHand: busted.sorted(), chipsByPlayer: chipsByPlayer)
        handNumber += 1
        return outcome
    }

    // MARK: - Street / card narration

    /// Emits `streetBegan` + the freshly dealt cards for every street opened since
    /// `announced` (handles multiple streets advancing at once during an all-in runout).
    private func announceNewStreets(_ announced: inout StudStreet, hand: StudHand) async {
        while announced.rawValue < hand.street.rawValue {
            let s = StudStreet(rawValue: announced.rawValue + 1)!
            announced = s
            await emit(.streetBegan(street: s))
            if s.dealsUpCard {
                let idx = s.rawValue - 3   // fourth→1, fifth→2, sixth→3
                for seat in hand.seats where !seat.hasFolded && seat.upCards.count > idx {
                    await emit(.upCardDealt(seatID: seat.id, card: seat.upCards[idx], street: s))
                }
            } else if let community = hand.communityCard {
                await emit(.communityCardDealt(card: community))
            } else {
                for seat in hand.seats where !seat.hasFolded {
                    await emit(.holeCardsDealt(seatID: seat.id))
                    if let last = seat.holeCards.last {
                        await emit(.privateDownCards(seatID: seat.id, cards: [last]), to: .player(seat.id))
                    }
                }
            }
        }
    }

    // MARK: - Table ↔ engine mapping

    private func eligibleParticipants() -> [StudSessionPlayer] {
        positions.compactMap { $0 }.filter { $0.chips > 0 }.sorted { $0.position < $1.position }
    }

    /// The winners of a pot for narration: eligible seats reduced to the best evaluated
    /// hand at showdown (fold-out → the single eligible seat).
    private func potWinners(_ pot: Pot, _ result: StudResult) -> [Int] {
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

    private func setChips(_ id: Int, to chips: Int) {
        guard let index = positions.firstIndex(where: { $0?.id == id }) else { return }
        positions[index]?.chips = chips
        positions[index]?.status = chips == 0 ? .bustedOut : .active
    }

    /// Defensively coerce a requested action to a legal one (fallback check/fold), so the
    /// driver stays total even with a misbehaving provider (D-013).
    private func legalizeAction(_ action: StudAction, _ legal: StudLegalActions) -> StudAction {
        switch action {
        case .fold:  return .fold
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

    private func classify(_ action: StudAction, toStreetBet: Int, currentBetBefore: Int,
                          committed: Int, isAllIn: Bool) -> StudActedAction {
        switch action {
        case .fold:  return .folded
        case .check: return .checked
        default:
            if toStreetBet <= currentBetBefore {
                return .called(amount: committed, isAllIn: isAllIn)
            } else if currentBetBefore == 0 {
                return .bet(to: toStreetBet, amount: committed, isAllIn: isAllIn)
            } else {
                return .raised(to: toStreetBet, amount: committed, isAllIn: isAllIn)
            }
        }
    }

    /// The seed for a hand: deterministic from the base seed (tests) or a fresh random
    /// draw (production), so no two hands repeat (D-047).
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
            seats: players.map { StudSeatSnapshot(seatID: $0.id, position: $0.position, chips: $0.chips) },
            ante: ante, bringIn: bringIn, bet: bet))
    }

    private func flushPendingStructuralEvents() async {
        let pending = pendingStructuralEvents
        pendingStructuralEvents.removeAll()
        for payload in pending { await emit(payload) }
    }
}
