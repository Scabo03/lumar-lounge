// MachiavelliSessionDriver.swift
// =====================================================================
// The Machiavelli session driver: the orchestrator that turns the pure engine into a
// playable GAME — deals the two-deck shoe, runs turns in order, lets each seat rework
// the shared table through the engine's turn model, and ends when a player empties
// their hand. Sister to `SessionDriver`/`DrawSessionDriver`/`OmahaSessionDriver`, with
// its own distinct event stream.
//
// It is a pure CLIENT of GameEngine: it validates every turn plan through the SAME
// `MachiavelliTurnContext` predicate a human would use (single source of truth,
// D-070), so a bot cannot cheat the rules; a malformed plan is defensively coerced to
// a draw (D-013). All consolidated principles hold: events are DESCRIPTIVE not
// prescriptive; the producer knows nothing of human ritmo; private events (a player's
// dealt hand, a drawn card) are addressed to that player only; bots receive a REDACTED
// context (public table + stock size + opponents' counts, never their cards, D-009).
//
// SEED POLICY (D-047, not re-discovered): with a base seed (tests) the shoe is
// deterministic; with `nil` (production) each game draws a FRESH RANDOM shoe from the
// system RNG. THE AUDIBLE WAIT (D-070): every bot turn is bracketed by thinking events
// carrying the bot's expected deliberation, so a future UI/audio can fill the silence.
//
// GameWorld only.

import Foundation
import GameEngine

/// Drives one Machiavelli game to completion at a single table.
public final class MachiavelliSessionDriver {

    // MARK: Fixed configuration

    public let capacity: Int
    public let handSize: Int

    /// Base seed. Set (tests) → deterministic shoe; `nil` (production) → fresh random
    /// shoe per game (D-047). The engine stays deterministic given whatever seed it gets.
    private let baseSeed: UInt64?

    // MARK: Mutable table state

    private var positions: [MachiavelliSessionPlayer?]
    private var providers: [Int: MachiavelliTurnProvider]
    private var hands: [Int: [Card]] = [:]
    private var table: [Meld] = []
    private var stock: [Card] = []
    public private(set) var gameNumber = 0
    public private(set) var isGameInProgress = false
    public private(set) var isGameOver = false
    public private(set) var hasEnded = false

    /// Safety bound guaranteeing termination even if no one can ever go out. Also
    /// lets tests cap a game to a handful of turns (resolved as a stalemate to the
    /// fewest-cards holder) so session-machinery tests run fast.
    private let maxTurns: Int

    // MARK: Event stream

    private let hub = MachiavelliEventHub()
    private var sessionAnnounced = false

    // MARK: - Init

    /// - Parameter seed: base seed for a DETERMINISTIC shoe (tests inject a fixed value).
    ///   Pass `nil` (production default) to draw a fresh random shoe (D-047).
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
    }

    // MARK: - Queries

    public var players: [MachiavelliSessionPlayer] {
        positions.compactMap { $0 }.sorted { $0.position < $1.position }
    }
    public func handCount(of id: Int) -> Int? { hands[id]?.count }
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
        await emit(.sessionEnded(reason: reason))
        await hub.finishAll()
    }

    // MARK: - Playing one game

    /// Deals a fresh game and plays it to completion (someone empties their hand, or a
    /// stalemate is resolved to the player holding the fewest cards).
    @discardableResult
    public func playGame() async throws -> MachiavelliGameOutcome {
        guard !hasEnded else { throw MachiavelliSessionError.sessionEnded }
        guard !isGameInProgress else { throw MachiavelliSessionError.gameInProgress }
        let participants = players
        guard participants.count >= 2 else { throw MachiavelliSessionError.notEnoughPlayers }

        isGameInProgress = true
        isGameOver = false
        defer { isGameInProgress = false }

        await announceSessionIfNeeded()
        deal(participants)

        let order = participants
        await emit(.gameBegan(seats: snapshots(order), firstToActSeatID: order[0].id, stockCount: stock.count))
        for player in order {
            await emit(.handDealt(seatID: player.id, count: hands[player.id]!.count))
            await emit(.privateHand(seatID: player.id, cards: hands[player.id]!), to: .player(player.id))
        }

        var idx = 0
        var turns = 0
        var stalemateRun = 0

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
            await emit(.turnEnded(seatID: seatID, ending: ending, handCount: hands[seatID]!.count))
            setHandCount(seatID)

            if hands[seatID]!.isEmpty {
                await emit(.playerWon(seatID: seatID))
                let outcome = MachiavelliGameOutcome(winnerID: seatID, turnsPlayed: turns,
                                                     handCounts: currentHandCounts())
                await emit(.gameEnded(winnerID: seatID, turnsPlayed: turns))
                isGameOver = true
                gameNumber += 1
                return outcome
            }

            // Stalemate detection: a full round of draw-only turns with an empty stock.
            if case .drew = ending, stock.isEmpty { stalemateRun += 1 } else { stalemateRun = 0 }
            if stalemateRun >= order.count { break }

            idx = (idx + 1) % order.count
        }

        // No one went out (stalemate / turn cap): the fewest-cards holder wins.
        let winner = order.min { (hands[$0.id]!.count, $0.id) < (hands[$1.id]!.count, $1.id) }!.id
        await emit(.playerWon(seatID: winner))
        let outcome = MachiavelliGameOutcome(winnerID: winner, turnsPlayed: turns,
                                             handCounts: currentHandCounts())
        await emit(.gameEnded(winnerID: winner, turnsPlayed: turns))
        isGameOver = true
        gameNumber += 1
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
        var shoe = MachiavelliRules.shoe(seed: gameSeed(gameNumber))
        hands = [:]
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

    private func currentHandCounts() -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: hands.map { ($0.key, $0.value.count) })
    }

    private func setHandCount(_ id: Int) {
        guard let index = positions.firstIndex(where: { $0?.id == id }) else { return }
        positions[index]?.handCount = hands[id]?.count ?? 0
    }

    /// The shoe seed for a game: deterministic from the base seed + game number (tests),
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
        await emit(.sessionBegan(seats: snapshots(players), handSize: handSize, stockCount: MachiavelliConstants.totalCards))
    }
}
