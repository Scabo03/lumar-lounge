// MachiavelliSessionDriver.swift
// =====================================================================
// The Machiavelli session driver: the orchestrator that turns the pure engine into a
// playable MATCH (partita) — a SEQUENCE of hands, each dealt fresh and SCORED at its
// end (D-071), until a player crosses the victory threshold. This mirrors the poker
// session driver's hand/session split: a HAND ends when a player goes out (or a
// stalemate is resolved); the MATCH accumulates scores across hands and ends at the
// threshold.
//
// Scoring is game logic and lives in the ENGINE (`MachiavelliScoring`); the driver only
// TRACKS the inputs (what each player placed, what they held) and feeds them to the
// pure scorer. The threshold and the match structure are a SESSION mechanic and live
// HERE in GameWorld, exactly as the decisive-hand boost, the progressive ante and
// `StakeEscalation` do (D-071).
//
// It is a pure CLIENT of GameEngine: it validates every turn plan through the SAME
// `MachiavelliTurnContext` predicate a human would use (single source of truth), so a
// bot cannot cheat the rules; a malformed plan is defensively coerced to a draw (D-013).
// Events are DESCRIPTIVE not prescriptive; the producer knows nothing of human ritmo;
// private events (a player's dealt hand, a drawn card) are addressed to that player
// only; bots receive a REDACTED context (D-009). Seed policy D-047. The audible-wait
// thinking events bracket every bot turn (D-070). GameWorld only.

import Foundation
import GameEngine

/// Drives a Machiavelli MATCH (a scored sequence of hands) at a single table.
public final class MachiavelliSessionDriver {

    /// Default cumulative points to win a match (D-071). A SESSION mechanic, so it lives
    /// here in GameWorld, not in the engine. Calibrated (D-071) so a bot match runs a
    /// SHORT, DENSE handful of hands (~3): a single hand's leader scores ~90–120, so
    /// ~250 keeps the single deal from being the whole story without dragging on.
    public static let defaultVictoryThreshold = 250

    // MARK: Fixed configuration

    public let capacity: Int
    public let handSize: Int
    /// Cumulative points at which the match is won (D-071). A SESSION mechanic.
    public let victoryThreshold: Int

    /// Base seed. Set (tests) → deterministic shoe per hand; `nil` (production) → fresh
    /// random shoe per hand (D-047). The engine stays deterministic given its seed.
    private let baseSeed: UInt64?

    // MARK: Mutable table state

    private var positions: [MachiavelliSessionPlayer?]
    private var providers: [Int: MachiavelliTurnProvider]
    private var hands: [Int: [Card]] = [:]
    private var table: [Meld] = []
    private var stock: [Card] = []
    /// Cards each player has laid onto the table DURING the current hand (for scoring).
    private var placedThisHand: [Int: [Card]] = [:]

    public private(set) var handNumber = 0
    /// Cumulative match scores by player id.
    public private(set) var cumulativeScores: [Int: Int] = [:]
    public private(set) var isHandInProgress = false
    public private(set) var isMatchOver = false
    public private(set) var hasEnded = false
    /// Whether the `matchEnded` event has already been emitted (once per match).
    private var matchEndEmitted = false

    /// Per-hand turn safety bound (also lets tests cap a hand to a few turns → a
    /// stalemate scored to the fewest-cards holder). Per-match hand safety bound.
    private let maxTurnsPerHand: Int
    private let maxHandsPerMatch: Int

    // MARK: Event stream

    private let hub = MachiavelliEventHub()
    private var sessionAnnounced = false

    // MARK: - Init

    /// - Parameters:
    ///   - seed: base seed for a DETERMINISTIC shoe (tests). `nil` (production) draws a
    ///     fresh random shoe per hand (D-047).
    ///   - victoryThreshold: cumulative points to win the match (D-071).
    public init(capacity: Int,
                seats: [MachiavelliSeatAssignment],
                handSize: Int = MachiavelliConstants.handSize,
                victoryThreshold: Int = MachiavelliSessionDriver.defaultVictoryThreshold,
                seed: UInt64? = nil,
                turnLimit: Int = 4000,
                handLimit: Int = 200) {
        precondition((2...4).contains(capacity), "A Machiavelli table seats 2–4.")
        precondition(turnLimit > 0 && handLimit > 0, "limits must be positive.")
        precondition(victoryThreshold > 0, "victoryThreshold must be positive.")
        var ring: [MachiavelliSessionPlayer?] = Array(repeating: nil, count: capacity)
        var providerMap: [Int: MachiavelliTurnProvider] = [:]
        for seat in seats {
            precondition((0..<capacity).contains(seat.position), "Seat position out of range.")
            precondition(ring[seat.position] == nil, "Two players in one seat.")
            precondition(providerMap[seat.playerID] == nil, "Duplicate player id.")
            ring[seat.position] = MachiavelliSessionPlayer(id: seat.playerID, handCount: 0,
                                                           status: .active, position: seat.position)
            providerMap[seat.playerID] = seat.provider
        }
        self.capacity = capacity
        self.handSize = handSize
        self.victoryThreshold = victoryThreshold
        self.baseSeed = seed
        self.maxTurnsPerHand = turnLimit
        self.maxHandsPerMatch = handLimit
        self.positions = ring
        self.providers = providerMap
        for id in providerMap.keys { cumulativeScores[id] = 0 }
    }

    // MARK: - Queries

    public var players: [MachiavelliSessionPlayer] {
        positions.compactMap { $0 }.sorted { $0.position < $1.position }
    }
    public func handCount(of id: Int) -> Int? { hands[id]?.count }
    public func score(of id: Int) -> Int? { cumulativeScores[id] }
    /// Whether another hand can be dealt (match not over, not mid-hand, enough players).
    public var canDealNextHand: Bool {
        !hasEnded && !isMatchOver && !isHandInProgress && players.count >= 2 && handNumber < maxHandsPerMatch
    }
    public var stockCount: Int { stock.count }
    /// Total cards currently on the shared table — for card-conservation checks.
    public var tableCardCount: Int { table.reduce(0) { $0 + $1.size } }

    // MARK: - Event subscription

    public func events(as viewer: EventViewer = .spectator) async -> AsyncStream<MachiavelliSessionEvent> {
        await hub.subscribe(as: viewer)
    }

    private func emit(_ payload: MachiavelliEventPayload, to audience: EventAudience = .everyone) async {
        await hub.emit(payload, audience: audience)
    }

    public func endSession(reason: MachiavelliSessionEndReason = .stopped) async {
        guard !hasEnded else { return }
        hasEnded = true
        await announceSessionIfNeeded()
        // Guarantee `matchEnded` was emitted at least once — e.g. a UI that drove hands
        // one-by-one and stopped at the hand-cap (or because the player left) without a
        // threshold crossing never triggered it (D-072).
        await concludeMatchIfNeeded()
        await emit(.sessionEnded(reason: reason))
        await hub.finishAll()
    }

    // MARK: - Playing a whole match

    /// Plays hands, accumulating scores, until a player crosses the victory threshold
    /// (or the hand-count safety bound). Returns the match outcome.
    @discardableResult
    public func playMatch() async throws -> MachiavelliMatchOutcome {
        guard !hasEnded else { throw MachiavelliSessionError.sessionEnded }
        guard !isMatchOver else { throw MachiavelliSessionError.matchAlreadyOver }
        // Each `playHand` emits `matchEnded` itself once a player crosses the threshold
        // (so a UI that drives hands one-by-one, gated for pacing, still gets it). Here
        // we just keep dealing until that happens or the safety bound is hit.
        while !isMatchOver && handNumber < maxHandsPerMatch {
            _ = try await playHand()
        }
        await concludeMatchIfNeeded()      // covers the hand-cap case (no threshold crossed)
        return MachiavelliMatchOutcome(winnerID: matchWinnerID(),
                                       handsPlayed: handNumber, finalScores: cumulativeScores)
    }

    /// The current match leader (highest total, ties broken by lowest id).
    private func matchWinnerID() -> Int {
        players.max { (cumulativeScores[$0.id] ?? 0, -$0.id) < (cumulativeScores[$1.id] ?? 0, -$1.id) }!.id
    }

    /// Emits `matchEnded` once, marking the match over. Called when a player crosses the
    /// threshold (from `finishHand`) or when the hand-cap is reached (from `playMatch`).
    private func concludeMatchIfNeeded() async {
        guard !matchEndEmitted else { return }
        matchEndEmitted = true
        isMatchOver = true
        await emit(.matchEnded(winnerID: matchWinnerID(), handsPlayed: handNumber, finalScores: cumulativeScores))
    }

    // MARK: - Playing one hand

    /// Deals a fresh hand and plays it to its end (a player goes out, or a stalemate is
    /// resolved to the fewest-cards holder), scores it (D-071), and folds the points
    /// into the running match totals. Returns the hand outcome.
    @discardableResult
    public func playHand() async throws -> MachiavelliHandOutcome {
        guard !hasEnded else { throw MachiavelliSessionError.sessionEnded }
        guard !isHandInProgress else { throw MachiavelliSessionError.handInProgress }
        let order = players
        guard order.count >= 2 else { throw MachiavelliSessionError.notEnoughPlayers }

        isHandInProgress = true
        defer { isHandInProgress = false }

        await announceSessionIfNeeded()
        deal(order)

        await emit(.handBegan(handNumber: handNumber, seats: snapshots(order),
                              firstToActSeatID: order[handNumber % order.count].id, stockCount: stock.count))
        for player in order {
            await emit(.handDealt(seatID: player.id, count: hands[player.id]!.count))
            await emit(.privateHand(seatID: player.id, cards: hands[player.id]!), to: .player(player.id))
        }

        // Turn loop — first-to-act rotates by hand number for fairness.
        var idx = handNumber % order.count
        var turns = 0
        var stalemateRun = 0
        var wentOutID: Int?

        while turns < maxTurnsPerHand {
            let seatID = order[idx].id
            turns += 1
            await emit(.turnBegan(seatID: seatID))

            let provider = providers[seatID]!
            if provider.isBot {
                await emit(.botThinkingBegan(seatID: seatID, expectedDeliberation: provider.expectedDeliberation))
            }
            let context = buildContext(seatID: seatID, order: order)
            let plan = await provider.provideTurn(for: context)
            if provider.isBot { await emit(.botThinkingEnded(seatID: seatID)) }

            let ending = await applyPlan(plan, seatID: seatID)
            if case let .melded(placed, _) = ending { placedThisHand[seatID, default: []].append(contentsOf: placed) }
            await emit(.turnEnded(seatID: seatID, ending: ending, handCount: hands[seatID]!.count))
            setHandCount(seatID)

            if hands[seatID]!.isEmpty {
                wentOutID = seatID
                await emit(.playerWentOut(seatID: seatID))
                break
            }
            if case .drew = ending, stock.isEmpty { stalemateRun += 1 } else { stalemateRun = 0 }
            if stalemateRun >= order.count { break }        // stalemate: no one can progress

            idx = (idx + 1) % order.count
        }

        return await finishHand(order: order, wentOutID: wentOutID, turns: turns)
    }

    /// Scores the completed hand and folds it into the match totals.
    private func finishHand(order: [MachiavelliSessionPlayer], wentOutID: Int?, turns: Int) async -> MachiavelliHandOutcome {
        let results = order.map { player in
            MachiavelliScoring.PlayerHandResult(
                playerID: player.id,
                placed: placedThisHand[player.id] ?? [],
                remaining: hands[player.id] ?? [],
                wentOut: player.id == wentOutID)
        }
        let handScores = MachiavelliScoring.score(results)
        for (id, points) in handScores { cumulativeScores[id, default: 0] += points }

        let handCounts = Dictionary(uniqueKeysWithValues: order.map { ($0.id, hands[$0.id]!.count) })
        await emit(.handEnded(handNumber: handNumber, wentOutSeatID: wentOutID,
                              handScores: handScores, cumulativeScores: cumulativeScores))

        let outcome = MachiavelliHandOutcome(handNumber: handNumber, wentOutID: wentOutID, turnsPlayed: turns,
                                             handScores: handScores, cumulativeScores: cumulativeScores,
                                             handCounts: handCounts)
        handNumber += 1
        // If this hand carried a player past the victory threshold, the MATCH is over —
        // emit it now, so both `playMatch` and a hand-by-hand UI driver see it (D-072).
        if cumulativeScores.values.contains(where: { $0 >= victoryThreshold }) {
            await concludeMatchIfNeeded()
        }
        return outcome
    }

    // MARK: - Turn application

    private func applyPlan(_ plan: MachiavelliTurnPlan, seatID: Int) async -> MachiavelliTurnEnding {
        let before = table
        var ctx = MachiavelliTurnContext(playerID: seatID, hand: hands[seatID]!, table: table)

        if plan.terminal == .meld {
            let proposal = ctx.evaluate(plan.finalTable)
            if proposal.isLegal, !proposal.placedFromHand.isEmpty {
                try? ctx.apply(plan.finalTable)          // guaranteed to succeed here
                hands[seatID] = ctx.hand
                table = ctx.table
                let rearranged = didRearrange(before: before, after: ctx.table)
                await emit(.tableChanged(seatID: seatID, table: table.map { $0.cards },
                                         placed: proposal.placedFromHand, rearrangedExisting: rearranged))
                return .melded(placed: proposal.placedFromHand, rearrangedTable: rearranged)
            }
            // Illegal or empty meld → fall through to a draw (defensive, D-013).
        }

        // Draw terminal (or fallback).
        if let card = stock.first {
            stock.removeFirst()
            hands[seatID]!.append(card)
            await emit(.playerDrew(seatID: seatID, stockCount: stock.count))
            await emit(.privateDraw(seatID: seatID, card: card), to: .player(seatID))
            return .drew(fromStock: true)
        }
        return .drew(fromStock: false)      // empty stock → forced pass, no card
    }

    /// Whether existing table combinations were dismantled/recomposed (as opposed to a
    /// pure addition where every prior combination stays intact within one new meld).
    private func didRearrange(before: [Meld], after: [Meld]) -> Bool {
        let afterSets = after.map { Set($0.cards) }
        for meld in before {
            let s = Set(meld.cards)
            if !afterSets.contains(where: { $0.isSuperset(of: s) }) { return true }
        }
        return false
    }

    // MARK: - Setup helpers

    private func deal(_ participants: [MachiavelliSessionPlayer]) {
        var shoe = MachiavelliRules.shoe(seed: gameSeed(handNumber))
        hands = [:]
        placedThisHand = [:]
        for player in participants {
            hands[player.id] = Array(shoe.prefix(handSize))
            shoe.removeFirst(handSize)
        }
        stock = shoe
        table = []
        for player in participants { setHandCount(player.id) }
    }

    private func buildContext(seatID: Int, order: [MachiavelliSessionPlayer]) -> MachiavelliBotContext {
        let seats = order.map {
            MachiavelliPublicSeat(id: $0.id, handCount: hands[$0.id]!.count, isHero: $0.id == seatID)
        }
        return MachiavelliBotContext(heroSeatID: seatID, hand: hands[seatID]!, table: table,
                                     stockCount: stock.count, seats: seats)
    }

    private func snapshots(_ order: [MachiavelliSessionPlayer]) -> [MachiavelliSeatSnapshot] {
        order.map { MachiavelliSeatSnapshot(seatID: $0.id, position: $0.position, handCount: hands[$0.id]?.count ?? 0) }
    }

    private func setHandCount(_ id: Int) {
        guard let index = positions.firstIndex(where: { $0?.id == id }) else { return }
        positions[index]?.handCount = hands[id]?.count ?? 0
    }

    /// The shoe seed for a hand: deterministic from the base seed + hand number (tests),
    /// or a fresh random draw (production, D-047).
    private func gameSeed(_ number: Int) -> UInt64 {
        guard let baseSeed else { return UInt64.random(in: .min ... .max) }
        var z = baseSeed &+ (UInt64(bitPattern: Int64(number)) &* 0x9E37_79B9_7F4A_7C15)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    private func announceSessionIfNeeded() async {
        guard !sessionAnnounced else { return }
        sessionAnnounced = true
        await emit(.sessionBegan(seats: snapshots(players), handSize: handSize, victoryThreshold: victoryThreshold))
    }
}
