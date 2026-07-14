// MachiavelliSessionDriver.swift
// =====================================================================
// The Machiavelli session driver: the orchestrator that turns the pure engine into a
// playable GAME — a SINGLE HAND. Whoever GOES OUT (empties their hand) wins the game;
// the end of the hand is the end of the game (D-075). We tried a multi-hand match with a
// points threshold (D-071), but the measure was taken between BOTS: the real test with
// VoiceOver reversed it — a single hand is already long (a human Machiavelli turn is
// WORK, not a decision), and three hands ran ~an hour. So the match structure is gone;
// the SCORING survives but changes purpose (a partial buy-in refund, computed in the UI
// from the final scores — D-075).
//
// Scoring is game logic and lives in the ENGINE (`MachiavelliScoring`, untouched); the
// driver only TRACKS the inputs (what each player placed, what they held) and feeds them
// to the pure scorer. The refund and the economy are a SESSION mechanic and live in
// GameWorld (the VM + `MachiavelliRefund`), where buy-in and persistent chips already live.
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

/// Drives a single-hand Machiavelli game at a single table (D-075).
public final class MachiavelliSessionDriver {

    // MARK: Fixed configuration

    public let capacity: Int
    public let handSize: Int

    /// Base seed. Set (tests) → deterministic shoe; `nil` (production) → fresh random
    /// shoe (D-047). The engine stays deterministic given its seed.
    private let baseSeed: UInt64?

    // MARK: Mutable table state

    private var positions: [MachiavelliSessionPlayer?]
    private var providers: [Int: MachiavelliTurnProvider]
    private var hands: [Int: [Card]] = [:]
    private var table: [Meld] = []
    private var stock: [Card] = []
    /// Cards each player has laid onto the table during the hand (for scoring).
    private var placedThisHand: [Int: [Card]] = [:]

    /// Whether the (single) hand has been played yet.
    public private(set) var handPlayed = false
    /// The final scores of the hand, by player id.
    public private(set) var scores: [Int: Int] = [:]
    /// The winner of the game (the player who went out, or fewest cards on a stalemate).
    public private(set) var winnerID: Int?
    public private(set) var isHandInProgress = false
    public private(set) var isGameOver = false
    public private(set) var hasEnded = false
    private var gameConcluded = false

    /// Per-hand turn safety bound (also lets tests cap a hand → a stalemate scored to the
    /// fewest-cards holder).
    private let maxTurns: Int

    // MARK: Event stream

    private let hub = MachiavelliEventHub()
    private var sessionAnnounced = false

    // MARK: - Init

    /// - Parameter seed: base seed for a DETERMINISTIC shoe (tests). `nil` (production)
    ///   draws a fresh random shoe (D-047).
    public init(capacity: Int,
                seats: [MachiavelliSeatAssignment],
                handSize: Int = MachiavelliConstants.handSize,
                seed: UInt64? = nil,
                turnLimit: Int = 4000) {
        precondition((2...4).contains(capacity), "A Machiavelli table seats 2–4.")
        precondition(turnLimit > 0, "turnLimit must be positive.")
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
        self.baseSeed = seed
        self.maxTurns = turnLimit
        self.positions = ring
        self.providers = providerMap
        for id in providerMap.keys { scores[id] = 0 }
    }

    // MARK: - Queries

    public var players: [MachiavelliSessionPlayer] {
        positions.compactMap { $0 }.sorted { $0.position < $1.position }
    }
    public func handCount(of id: Int) -> Int? { hands[id]?.count }
    public func score(of id: Int) -> Int? { scores[id] }
    /// Whether the (one) hand can still be dealt.
    public var canDealNextHand: Bool {
        !hasEnded && !isGameOver && !isHandInProgress && !handPlayed && players.count >= 2
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
        // Guarantee the game-over event fired at least once (e.g. the session ended before
        // the hand was played — winner falls back to fewest cards).
        await concludeGameIfNeeded()
        await emit(.sessionEnded(reason: reason))
        await hub.finishAll()
    }

    // MARK: - Playing the game (one hand)

    /// Plays the single hand and returns the game outcome. A convenience wrapper over
    /// `playHand` for callers/tests that want the result in one call.
    @discardableResult
    public func playMatch() async throws -> MachiavelliMatchOutcome {
        guard !hasEnded else { throw MachiavelliSessionError.sessionEnded }
        guard !isGameOver else { throw MachiavelliSessionError.matchAlreadyOver }
        if !handPlayed { _ = try await playHand() }
        await concludeGameIfNeeded()
        return MachiavelliMatchOutcome(winnerID: winnerID ?? fewestCardsPlayer(),
                                       handsPlayed: 1, finalScores: scores)
    }

    /// The player holding the fewest cards (ties broken by lowest id) — the stalemate winner.
    private func fewestCardsPlayer() -> Int {
        players.min { (hands[$0.id]?.count ?? 0, $0.id) < (hands[$1.id]?.count ?? 0, $1.id) }!.id
    }

    /// Emits the game-over event once. The winner is the player who went out, or — on a
    /// stalemate — the fewest-cards holder (D-075).
    private func concludeGameIfNeeded() async {
        guard !gameConcluded else { return }
        gameConcluded = true
        isGameOver = true
        let winner = winnerID ?? fewestCardsPlayer()
        winnerID = winner
        await emit(.matchEnded(winnerID: winner, handsPlayed: handPlayed ? 1 : 0, finalScores: scores))
    }

    // MARK: - Playing the hand

    /// Deals the hand and plays it to its end (a player goes out, or a stalemate is
    /// resolved to the fewest-cards holder), scores it (D-071), then concludes the game.
    @discardableResult
    public func playHand() async throws -> MachiavelliHandOutcome {
        guard !hasEnded else { throw MachiavelliSessionError.sessionEnded }
        guard !isHandInProgress else { throw MachiavelliSessionError.handInProgress }
        guard !handPlayed else { throw MachiavelliSessionError.matchAlreadyOver }
        let order = players
        guard order.count >= 2 else { throw MachiavelliSessionError.notEnoughPlayers }

        isHandInProgress = true
        defer { isHandInProgress = false }

        await announceSessionIfNeeded()
        deal(order)

        await emit(.handBegan(handNumber: 0, seats: snapshots(order),
                              firstToActSeatID: order[0].id, stockCount: stock.count))
        for player in order {
            await emit(.handDealt(seatID: player.id, count: hands[player.id]!.count))
            await emit(.privateHand(seatID: player.id, cards: hands[player.id]!), to: .player(player.id))
        }

        var idx = 0
        var turns = 0
        var stalemateRun = 0
        var wentOutID: Int?

        while turns < maxTurns {
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

        let outcome = await finishHand(order: order, wentOutID: wentOutID, turns: turns)
        await concludeGameIfNeeded()      // going out (or the stalemate resolution) ends the game
        return outcome
    }

    /// Scores the completed hand (D-071) and records the winner (the out player, or the
    /// fewest-cards holder on a stalemate — set here so `concludeGame` uses it).
    private func finishHand(order: [MachiavelliSessionPlayer], wentOutID: Int?, turns: Int) async -> MachiavelliHandOutcome {
        let results = order.map { player in
            MachiavelliScoring.PlayerHandResult(
                playerID: player.id,
                placed: placedThisHand[player.id] ?? [],
                remaining: hands[player.id] ?? [],
                wentOut: player.id == wentOutID)
        }
        let handScores = MachiavelliScoring.score(results)
        scores = handScores
        winnerID = wentOutID ?? fewestCardsPlayer()   // whoever went out wins (D-075)
        handPlayed = true

        let handCounts = Dictionary(uniqueKeysWithValues: order.map { ($0.id, hands[$0.id]!.count) })
        await emit(.handEnded(handNumber: 0, wentOutSeatID: wentOutID,
                              handScores: handScores, cumulativeScores: handScores))

        return MachiavelliHandOutcome(handNumber: 0, wentOutID: wentOutID, turnsPlayed: turns,
                                      handScores: handScores, cumulativeScores: handScores,
                                      handCounts: handCounts)
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
        var shoe = MachiavelliRules.shoe(seed: gameSeed())
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

    /// The shoe seed: deterministic from the base seed (tests), or a fresh random draw
    /// (production, D-047).
    private func gameSeed() -> UInt64 {
        guard let baseSeed else { return UInt64.random(in: .min ... .max) }
        var z = baseSeed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    private func announceSessionIfNeeded() async {
        guard !sessionAnnounced else { return }
        sessionAnnounced = true
        await emit(.sessionBegan(seats: snapshots(players), handSize: handSize))
    }
}
