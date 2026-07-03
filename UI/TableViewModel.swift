// TableViewModel.swift
// =====================================================================
// Owns the demonstration session and turns its code-speed event stream into a
// human-paced, observable `TableState` for the view — plus VoiceOver narration.
//
// This is where HUMAN TIME meets the driver's code time (D-018): the driver
// (M1.4/M1.5) emits instantly; this view model consumes at a watchable rhythm,
// sleeping between events (different rhythms per event; flop cards one by one),
// and gates the producer so it never runs more than a hand ahead.
//
// It contains NO game logic — it listens (events) and shows (state). All rules
// live in GameEngine; all orchestration in GameWorld.

import Foundation
import GameWorld
import GameEngine

@MainActor
public final class TableViewModel: ObservableObject {

    @Published public private(set) var state: TableState

    /// Localized display names per seat id.
    public let names: [Int: String]

    private let driver: SessionDriver
    private let announcer = Announcer()
    private let gate = HandGate()

    public init() {
        // Three bots of visibly different character (M1.3 personalities).
        let roster: [(id: Int, personality: Personality, nameKey: String)] = [
            (0, .eagerNovice, "seat.name.novice"),
            (1, .conservativeRock, "seat.name.rock"),
            (2, .hotAggressor, "seat.name.aggressor"),
        ]
        let startingChips = 1000
        let seats = roster.map { entry in
            SeatAssignment(position: entry.id, playerID: entry.id, chips: startingChips,
                           provider: BotActionProvider(HeuristicBot(personality: entry.personality,
                                                                     seed: UInt64(entry.id + 1) * 101,
                                                                     equitySamples: 120)))
        }
        self.driver = SessionDriver(capacity: roster.count, seats: seats, buttonPosition: 0,
                                    smallBlind: 10, bigBlind: 20, seed: 20_260_703)
        self.names = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, uiLocalized($0.nameKey)) })

        // Pre-populate the table so it renders (and is accessible) immediately.
        self.state = TableState(
            seats: roster.map { SeatPresentation(id: $0.id, position: $0.id, chips: startingChips) },
            phase: .idle
        )
    }

    /// Runs the demo: subscribes to the public stream, plays hands at code speed
    /// (producer) and narrates them at human speed (consumer), until one bot has
    /// all the chips. Cancels cleanly when the surrounding `.task` is cancelled.
    public func run() async {
        let stream = await driver.events(as: .spectator)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.produce() }
            group.addTask { await self.consume(stream) }
        }
    }

    // MARK: - Producer (code speed, gated one hand ahead)

    private func produce() async {
        while !Task.isCancelled && driver.canDealNextHand {
            await gate.acquire()
            if Task.isCancelled { break }
            _ = try? await driver.playHand()
        }
        await driver.endSession()
    }

    // MARK: - Consumer (human paced)

    private func consume(_ stream: AsyncStream<SessionEvent>) async {
        for await event in stream {
            if Task.isCancelled { break }
            await present(event.payload)
        }
    }

    private func present(_ payload: EventPayload) async {
        // The flop is revealed one card at a time so each can be heard.
        if case let .streetOpened(.flop, cards) = payload {
            announce(uiLocalized("announce.street.flop.header"))
            for card in cards {
                state = TableReducer.reduce(state, .streetOpened(street: .flop, communityCards: [card]))
                announce(CardText.spoken(card))
                await pause(0.6)
            }
            await pause(0.3)
            return
        }

        state = TableReducer.reduce(state, payload)
        if let message = narration(for: payload) { announce(message) }
        await pause(paceSeconds(for: payload))
    }

    // MARK: - Narration

    private func narration(for payload: EventPayload) -> String? {
        if case .sessionEnded = payload {
            guard let winnerID = state.winnerSeatID else { return nil }
            return TableAnnouncer.text(for: .winner(who: name(winnerID)))
        }
        guard let spoken = TableAnnouncer.spoken(for: payload, names: names) else { return nil }
        return TableAnnouncer.text(for: spoken)
    }

    private func announce(_ message: String) {
        announcer.announce(message)
    }

    private func name(_ id: Int) -> String { names[id] ?? "\(id)" }

    // MARK: - Human rhythm

    private func paceSeconds(for payload: EventPayload) -> Double {
        switch payload {
        case .sessionBegan: return 0.7
        case .handBegan: return 0.9
        case .blindPosted: return 0.5
        case .holeCardsDealt: return 0.25
        case .playerActed: return 0.65
        case .streetOpened: return 0.7   // turn / river (single card)
        case .handShown: return 1.1
        case .potAwarded: return 1.2
        case .handEnded: return 1.4
        case .playerBusted: return 1.1
        case .sessionEnded: return 0.0
        default: return 0.3
        }
    }

    private func pause(_ seconds: Double) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
