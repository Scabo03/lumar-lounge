// SessionDriver.swift
// =====================================================================
// The session driver: the orchestrator that turns single hands (GameEngine's
// `HoldemHand`) into a SESSION — a run of hands at one table by the same
// players, with chips carried across hands, busts, dead-button rotation, and
// players joining/leaving between hands.
//
// It is a pure CLIENT of GameEngine (D-014): it never modifies the engine nor
// reaches into its internals. It creates a `HoldemHand`, drives it by reading
// `legalActions()` (via the redacted `BotContext`) and calling `apply(_:)`, and
// reads the `HandResult`. Bots and humans answer through the same uniform
// `ActionProvider` async interface (D-013).
//
// The session-end decision lives OUTSIDE the driver (the caller loops on
// `playHand()` / `run(...)` and decides when to stop). GameWorld only.

import Foundation
import GameEngine

/// Drives a multi-hand Texas Hold'em session at a single table.
///
/// A reference type: it holds evolving table state and is stepped one hand at a
/// time. Structural changes (join/leave) are only allowed between hands.
public final class SessionDriver {

    // MARK: Fixed configuration

    /// Number of physical seats in the ring (2…10). The button rotates through
    /// these positions, empty ones included.
    public let capacity: Int
    public let smallBlind: Int
    public let bigBlind: Int
    private let baseSeed: UInt64

    // MARK: Mutable table state

    /// The ring of physical seats; `nil` is an empty seat.
    private var positions: [SessionPlayer?]
    /// Who answers for each seated player id.
    private var providers: [Int: ActionProvider]
    /// Physical button position (ring index).
    public private(set) var buttonPosition: Int
    /// Number of hands played so far (also the next hand's index).
    public private(set) var handNumber: Int
    /// True while a hand is being played (guards joins/leaves and reentrancy).
    public private(set) var isHandInProgress: Bool = false

    // MARK: - Init

    /// - Parameters:
    ///   - capacity: ring size, 2…10.
    ///   - seats: initial seating (unique positions in range, unique ids,
    ///     positive chips).
    ///   - buttonPosition: initial physical button position.
    ///   - smallBlind/bigBlind: positive, `smallBlind <= bigBlind`.
    ///   - seed: base seed; each hand derives a deterministic per-hand seed.
    public init(capacity: Int,
                seats: [SeatAssignment],
                buttonPosition: Int,
                smallBlind: Int,
                bigBlind: Int,
                seed: UInt64) {
        precondition((2...10).contains(capacity), "A table seats 2–10.")
        precondition((0..<capacity).contains(buttonPosition), "Button position out of range.")
        precondition(smallBlind > 0 && bigBlind > 0 && smallBlind <= bigBlind, "Invalid blinds.")

        var ring: [SessionPlayer?] = Array(repeating: nil, count: capacity)
        var providerMap: [Int: ActionProvider] = [:]
        for seat in seats {
            precondition((0..<capacity).contains(seat.position), "Seat position out of range.")
            precondition(ring[seat.position] == nil, "Two players in one seat.")
            precondition(providerMap[seat.playerID] == nil, "Duplicate player id.")
            precondition(seat.chips > 0, "A seated player needs positive chips.")
            ring[seat.position] = SessionPlayer(id: seat.playerID, chips: seat.chips,
                                                status: .active, position: seat.position)
            providerMap[seat.playerID] = seat.provider
        }

        self.capacity = capacity
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.baseSeed = seed
        self.positions = ring
        self.providers = providerMap
        self.buttonPosition = buttonPosition
        self.handNumber = 0
    }

    // MARK: - Queries

    /// All seated players, in clockwise (position) order.
    public var players: [SessionPlayer] {
        positions.compactMap { $0 }.sorted { $0.position < $1.position }
    }

    public func player(_ id: Int) -> SessionPlayer? {
        positions.compactMap { $0 }.first { $0.id == id }
    }

    public func chips(of id: Int) -> Int? { player(id)?.chips }

    /// Seated players that still have chips and can be dealt in.
    public var eligiblePlayerCount: Int {
        positions.compactMap { $0 }.reduce(0) { $0 + ($1.chips > 0 ? 1 : 0) }
    }

    /// Whether another hand can start right now.
    public var canDealNextHand: Bool { eligiblePlayerCount >= 2 && !isHandInProgress }

    // MARK: - Structural changes (between hands only)

    /// Seats a new player. Allowed only between hands (never mid-hand).
    public func addPlayer(id: Int, chips: Int, at position: Int, provider: ActionProvider) throws {
        guard !isHandInProgress else { throw SessionError.handInProgress }
        guard (0..<capacity).contains(position) else { throw SessionError.positionOutOfRange(position) }
        guard positions[position] == nil else { throw SessionError.positionOccupied(position) }
        guard player(id) == nil, providers[id] == nil else { throw SessionError.duplicatePlayerID(id) }
        guard chips > 0 else { throw SessionError.nonPositiveChips }
        positions[position] = SessionPlayer(id: id, chips: chips, status: .active, position: position)
        providers[id] = provider
    }

    /// Removes a player, freeing its seat. Allowed only between hands.
    public func removePlayer(id: Int) throws {
        guard !isHandInProgress else { throw SessionError.handInProgress }
        guard let seated = player(id) else { throw SessionError.unknownPlayer(id) }
        positions[seated.position] = nil
        providers[id] = nil
    }

    // MARK: - Playing

    /// Plays exactly one hand to completion and returns its outcome.
    ///
    /// Afterwards, chips are updated, newly-busted players are marked, and the
    /// button advances one physical position (ready for the next hand).
    @discardableResult
    public func playHand() async throws -> HandOutcome {
        guard !isHandInProgress else { throw SessionError.handInProgress }
        let participants = eligibleParticipants()
        guard participants.count >= 2 else { throw SessionError.notEnoughPlayers }

        isHandInProgress = true
        defer { isHandInProgress = false }

        // Map the dead-button table onto the engine's participant-relative model.
        let engineSeats = participants.map { Seat(id: $0.id, stack: $0.chips) }
        let buttonID = engineButtonPlayerID()
        let engineButtonIndex = participants.firstIndex { $0.id == buttonID }!

        var hand = HoldemHand(seats: engineSeats,
                              buttonIndex: engineButtonIndex,
                              smallBlind: smallBlind,
                              bigBlind: bigBlind,
                              seed: handSeed(handNumber))

        // Drive the hand: ask the seat on turn, apply, repeat.
        while !hand.isComplete {
            guard let context = BotContext(actingIn: hand) else { break }
            let provider = providers[context.heroSeatID]
            let requested = await provider?.provideAction(for: context)
            let action = legalize(requested ?? .fold, context.legal)
            try hand.apply(action) // legalize guarantees legality → never throws here
        }

        let result = hand.result!
        var busted: [Int] = []
        for participant in participants {
            let finalStack = result.finalStacks[participant.id] ?? participant.chips
            setChips(participant.id, to: finalStack)
            if finalStack == 0 { busted.append(participant.id) }
        }

        let outcome = HandOutcome(
            handNumber: handNumber,
            buttonPosition: buttonPosition,
            participantIDs: participants.map { $0.id },
            result: result,
            bustedThisHand: busted.sorted(),
            chipsByPlayer: Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.chips) })
        )

        handNumber += 1
        buttonPosition = (buttonPosition + 1) % capacity // dead button: advance by position
        return outcome
    }

    /// Convenience loop: plays hands while it can and while `shouldContinue`
    /// (the CALLER's stop criterion — the driver never decides this) allows.
    @discardableResult
    public func run(maxHands: Int = .max,
                    continuing shouldContinue: (HandOutcome) -> Bool = { _ in true }) async throws -> [HandOutcome] {
        var outcomes: [HandOutcome] = []
        while outcomes.count < maxHands && canDealNextHand {
            let outcome = try await playHand()
            outcomes.append(outcome)
            if !shouldContinue(outcome) { break }
        }
        return outcomes
    }

    // MARK: - Table ↔ engine mapping

    /// The eligible participants for a hand, in clockwise (position) order.
    private func eligibleParticipants() -> [SessionPlayer] {
        positions.compactMap { $0 }.filter { $0.chips > 0 }.sorted { $0.position < $1.position }
    }

    /// The player id the engine should treat as the button.
    ///
    /// Dead-button rule: the physical button may sit on an empty/busted seat.
    /// The engine needs a real participant, so we use the first eligible player
    /// found scanning counter-clockwise from the physical button (inclusive).
    /// Its clockwise-next participant is exactly the real small blind, so the
    /// action order the engine produces matches the dead button precisely.
    private func engineButtonPlayerID() -> Int {
        for step in 0..<capacity {
            let position = (buttonPosition - step + capacity) % capacity
            if let seated = positions[position], seated.chips > 0 {
                return seated.id
            }
        }
        preconditionFailure("No eligible player for the button.")
    }

    // MARK: - Helpers

    private func setChips(_ id: Int, to chips: Int) {
        guard let index = positions.firstIndex(where: { $0?.id == id }) else { return }
        positions[index]?.chips = chips
        positions[index]?.status = chips == 0 ? .bustedOut : .active
    }

    /// Coerces a provider's action to a guaranteed-legal one. On a violation it
    /// falls back to the safest move (check if free, otherwise fold) so the
    /// driver stays total and deterministic even against a misbehaving provider.
    private func legalize(_ action: Action, _ legal: LegalActions) -> Action {
        isPermitted(action, legal) ? action : (legal.canCheck ? .check : .fold)
    }

    private func isPermitted(_ action: Action, _ legal: LegalActions) -> Bool {
        switch action {
        case .fold: return legal.canFold
        case .check: return legal.canCheck
        case .call: return legal.canCall
        case .bet(let n): return legal.canBet && n >= legal.minBetTo && n <= legal.maxBetTo
        case .raise(let n): return legal.canRaise && n >= legal.minRaiseTo && n <= legal.maxRaiseTo
        case .allIn: return legal.canAllIn
        }
    }

    /// Deterministic per-hand seed (SplitMix64 over base seed + hand number).
    private func handSeed(_ number: Int) -> UInt64 {
        var z = baseSeed &+ (UInt64(bitPattern: Int64(number)) &* 0x9E37_79B9_7F4A_7C15)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
