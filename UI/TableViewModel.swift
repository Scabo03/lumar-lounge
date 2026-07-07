// TableViewModel.swift
// =====================================================================
// Owns the session (human + three bots), turns its code-speed event stream into
// a human-paced, observable `TableState`, narrates it to VoiceOver, and drives
// the human's turn: shows the action buttons when it's the human's move and
// forwards the chosen `Action` to the M1.4 `HumanActionProvider` (D-021).
//
// Human-turn synchronisation (D-021): the stream is relayed into a MainActor
// queue this model controls. When the queue is drained AND the human provider is
// waiting (`pendingContext != nil`), the paced display has caught up to the
// human's decision point — so that is exactly when the buttons appear. The
// producer naturally blocks on the human, so it never runs past the turn.
//
// No game logic lives here — it listens, shows, and forwards input. Rules stay
// in GameEngine; orchestration in GameWorld.

import Foundation
import GameWorld
import GameEngine
import Audio

/// The information the action bar needs when it's the human's turn.
public struct HumanTurnInfo: Equatable, Sendable {
    public let toCall: Int
    public let potSize: Int
    public let heroStack: Int
    public let canFold: Bool
    public let canCheck: Bool
    public let canCall: Bool
    public let callAmount: Int
    public let canBetOrRaise: Bool
    public let isBet: Bool
    public let minTo: Int
    public let maxTo: Int
    public let canAllIn: Bool

    init(from context: BotContext) {
        let legal = context.legal
        toCall = context.toCall
        potSize = context.potSize
        heroStack = context.heroStack
        canFold = legal.canFold
        canCheck = legal.canCheck
        canCall = legal.canCall
        callAmount = legal.callAmount
        canAllIn = legal.canAllIn
        if legal.canBet {
            canBetOrRaise = true; isBet = true; minTo = legal.minBetTo; maxTo = legal.maxBetTo
        } else if legal.canRaise {
            canBetOrRaise = true; isBet = false; minTo = legal.minRaiseTo; maxTo = legal.maxRaiseTo
        } else {
            canBetOrRaise = false; isBet = false; minTo = 0; maxTo = 0
        }
    }
}

/// The end-of-session outcome for the human.
public enum GameOutcome: Equatable, Sendable { case won, lost }

@MainActor
public final class TableViewModel: ObservableObject {

    @Published public private(set) var state: TableState
    /// Non-nil while it's the human's turn (the action buttons are then active).
    @Published public private(set) var humanTurn: HumanTurnInfo?
    /// Non-nil while the Raise box is open.
    @Published public private(set) var raiseBox: RaiseBoxState?
    /// Set once the session ends.
    @Published public private(set) var outcome: GameOutcome?

    public let names: [Int: String]
    public let heroSeatID = 0

    private let driver: SessionDriver
    private let human = HumanActionProvider()
    private let announcer = Announcer()
    private let gate = HandGate()
    private let fastMode: Bool
    private let audio: AudioServicing
    private let audioDirector: AudioDirector
    /// The serial owner of the croupier voice + VoiceOver synthesis (D-029).
    private let conductor: SpeechConductor

    private var eventQueue: [EventPayload] = []
    private var streamFinished = false
    private var turnContinuation: CheckedContinuation<Void, Never>?
    /// Each seat's hand category revealed at showdown, for the pot conclusion line.
    private var shownCategory: [Int: HandCategory] = [:]

    public init(seed: UInt64 = 20_260_704, fastMode: Bool = false,
                audio: AudioServicing = NullAudioService()) {
        self.fastMode = fastMode
        self.audio = audio
        // Seat 0 is the human (bottom of the screen); seats 1–3 are the bots.
        let bots: [(id: Int, personality: Personality, nameKey: String)] = [
            (1, .eagerNovice, "seat.name.novice"),
            (2, .conservativeRock, "seat.name.rock"),
            (3, .hotAggressor, "seat.name.aggressor"),
        ]
        let startingChips = 1000
        var assignments = [SeatAssignment(position: 0, playerID: 0, chips: startingChips, provider: human)]
        assignments += bots.map { bot in
            SeatAssignment(position: bot.id, playerID: bot.id, chips: startingChips,
                           provider: BotActionProvider(HeuristicBot(personality: bot.personality,
                                                                    seed: UInt64(bot.id) * 101 &+ seed,
                                                                    equitySamples: fastMode ? 30 : 120)))
        }
        self.driver = SessionDriver(capacity: 4, seats: assignments, buttonPosition: 0,
                                    smallBlind: 10, bigBlind: 20, seed: seed)

        var names = [0: uiLocalized("seat.name.you")]
        for bot in bots { names[bot.id] = uiLocalized(bot.nameKey) }
        self.names = names

        // Each bot's CHARACTER, so the audio director picks fitting voicelines.
        let characters: [Int: BotCharacter] = [1: .novice, 2: .rock, 3: .aggressor]
        self.audioDirector = AudioDirector(audio: audio, heroSeatID: 0, characters: characters,
                                           seed: seed, fastMode: fastMode)
        self.conductor = SpeechConductor(audio: audio, announcer: Announcer())

        self.state = TableState(
            seats: ([0] + bots.map { $0.id }).map { SeatPresentation(id: $0, position: $0, chips: startingChips) },
            phase: .idle, heroSeatID: 0
        )
    }

    // MARK: - Lifecycle

    /// Runs the session: relays the stream, plays hands (producer), and narrates
    /// them at human pace while handling the human's turns (consumer).
    public func run() async {
        // Two parallel subscribers to the same multicast flow: the display
        // (as the human player, to see its own cards) and the audio director
        // (as a spectator — audio needs no private cards).
        let display = await driver.events(as: .player(heroSeatID))
        let audioStream = await driver.events(as: .spectator)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.relay(display) }
            group.addTask { await self.produce() }
            group.addTask { await self.consume() }
            group.addTask { await self.audioDirector.run(audioStream) }
        }
    }

    private func relay(_ stream: AsyncStream<SessionEvent>) async {
        for await event in stream {
            eventQueue.append(event.payload)
        }
        streamFinished = true
    }

    private func produce() async {
        while !Task.isCancelled && driver.canDealNextHand {
            await gate.acquire()
            if Task.isCancelled { break }
            _ = try? await driver.playHand()
            // Stop as soon as the human busts (the bots may still have chips).
            if (driver.chips(of: heroSeatID) ?? 0) == 0 { break }
        }
        await driver.endSession()
    }

    private func consume() async {
        while !Task.isCancelled {
            if !eventQueue.isEmpty {
                await present(eventQueue.removeFirst())
            } else if let context = await human.pendingContext {
                await runHumanTurn(context)
            } else if streamFinished {
                break
            } else {
                try? await Task.sleep(nanoseconds: 30_000_000) // 30 ms idle poll
            }
        }
    }

    // MARK: - Presenting events (human paced)

    private func present(_ payload: EventPayload) async {
        switch payload {
        case .handBegan:
            conductor.handBegan()          // reset once-per-hand voices (D-029)
            shownCategory.removeAll()
            state = TableReducer.reduce(state, payload)
            speak(payload)                 // croupier: "new hand"
            await pause(Pacing.seconds(for: payload))

        case let .streetOpened(.flop, cards):
            // The croupier says "flop", then the conductor reads the three cards
            // (D-029). Meanwhile reveal them one at a time.
            speak(payload)
            for card in cards {
                state = TableReducer.reduce(state, .streetOpened(street: .flop, communityCards: [card]))
                await pause(0.55)
            }
            await pause(0.25)

        case let .privateHoleCards(seatID, _) where seatID == heroSeatID:
            state = TableReducer.reduce(state, payload)
            speak(payload)                 // synthesis: the human's own cards
            await pause(0.6)

        case let .playerActed(seatID, _):
            state.activeSeatID = seatID
            if seatID != heroSeatID { await pause(0.55) } // bot "thinking"
            state = TableReducer.reduce(state, payload)
            speak(payload)                 // croupier only if it's an all-in (D-029)
            await pause(0.4)
            if state.activeSeatID == seatID { state.activeSeatID = nil }

        case let .handShown(seatID, _, category, _):
            shownCategory[seatID] = category
            state = TableReducer.reduce(state, payload)
            speak(payload)                 // croupier "showdown" (once) + reveal
            await pause(Pacing.seconds(for: payload))

        case .potAwarded:
            state = TableReducer.reduce(state, payload)
            speakPot(payload)              // pot voice once/hand + "you won with …"
            await pause(1.1)

        case .handEnded:
            state = TableReducer.reduce(state, payload)
            await gate.release() // let the producer deal the next hand
            await pause(1.2)

        case .sessionEnded:
            state = TableReducer.reduce(state, payload)
            finishSession()

        default:
            // Blinds (croupier), turn/river handled above; public hole-cards-dealt,
            // busts, joins → the map decides (mostly silent for the spoken layer).
            state = TableReducer.reduce(state, payload)
            speak(payload)
            await pause(Pacing.seconds(for: payload))
        }
    }

    /// Sends an event's spoken plan (croupier and/or synthesis) to the conductor.
    private func speak(_ payload: EventPayload) {
        let plan = SpeechMap.plan(for: payload, heroSeatID: heroSeatID, names: names)
        conductor.say(croupier: plan.croupier, synthesis: plan.synthesis.map(SpeechMap.text))
    }

    /// The pot conclusion: the once-per-hand croupier pot voice plus a synthesis
    /// naming the winner and — if it went to showdown — the winning hand (D-029).
    private func speakPot(_ payload: EventPayload) {
        guard case let .potAwarded(_, _, winners) = payload else { return }
        let plan = SpeechMap.plan(for: payload, heroSeatID: heroSeatID, names: names)
        let line: SynthLine?
        if winners.contains(heroSeatID) {
            line = .heroWon(category: shownCategory[heroSeatID])
        } else if let winner = winners.first {
            line = .otherWon(who: winners.map { names[$0] ?? "\($0)" }.joined(separator: ", "),
                             category: shownCategory[winner])
        } else {
            line = nil
        }
        conductor.say(croupier: plan.croupier, synthesis: line.map(SpeechMap.text))
    }

    // MARK: - The human's turn

    private func runHumanTurn(_ context: BotContext) async {
        let info = HumanTurnInfo(from: context)
        humanTurn = info
        state.activeSeatID = heroSeatID
        // The croupier says "it's your turn" (vo_it_your_turn); synthesis adds the
        // call context only when there's something to call (D-029).
        let callContext: String? = info.toCall > 0
            ? SpeechMap.text(for: .yourTurnContext(toCall: info.toCall, pot: info.potSize))
            : nil
        conductor.say(croupier: SoundCatalog.voYourTurn, synthesis: callContext)
        await withCheckedContinuation { turnContinuation = $0 }
        humanTurn = nil
        raiseBox = nil
        if state.activeSeatID == heroSeatID { state.activeSeatID = nil }
    }

    /// Forwards the human's chosen action to the driver and resumes the turn.
    private func act(_ action: Action) {
        guard let continuation = turnContinuation else { return }
        turnContinuation = nil
        humanTurn = nil // hide immediately to prevent a double action
        raiseBox = nil
        Task {
            await human.submit(action)
            continuation.resume()
        }
    }

    // MARK: - Action-bar intents (called by the view)

    public func fold() { playUI(SoundCatalog.uiButtonTap); act(.fold) }

    public func checkOrCall() {
        guard let turn = humanTurn else { return }
        playUI(SoundCatalog.uiButtonTap)
        act(turn.canCheck ? .check : .call)
    }

    public func openRaiseBox() {
        guard let turn = humanTurn, turn.canBetOrRaise else { return }
        playUI(SoundCatalog.uiBoxOpen)
        let box = RaiseBoxState(minTo: turn.minTo, maxTo: turn.maxTo, isBet: turn.isBet)
        raiseBox = box
        // No announcement here: opening moves VoiceOver focus onto the box title,
        // which already speaks the dialog name and the starting amount (D-027).
    }

    public func raisePlus() {
        guard var box = raiseBox else { return }
        playUI(SoundCatalog.uiRaisePlus)
        box.increase(); raiseBox = box
        announce(uiLocalized("announce.raise.value", box.value), interrupting: true)
    }

    public func raiseMinus() {
        guard var box = raiseBox else { return }
        playUI(SoundCatalog.uiRaiseMinus)
        box.decrease(); raiseBox = box
        announce(uiLocalized("announce.raise.value", box.value), interrupting: true)
    }

    public func raiseAllIn() {
        guard var box = raiseBox else { return }
        playUI(SoundCatalog.uiAllInTrigger)
        box.toMax(); raiseBox = box
        announce(uiLocalized("announce.raise.allin", box.value), interrupting: true)
    }

    public func confirmRaise() {
        guard let box = raiseBox, let turn = humanTurn else { return }
        playUI(SoundCatalog.uiConfirm)
        let action: Action
        if box.isAtMax && turn.canAllIn {
            action = .allIn
        } else {
            action = box.isBet ? .bet(box.value) : .raise(box.value)
        }
        act(action)
    }

    public func cancelRaise() { playUI(SoundCatalog.uiBoxClose); raiseBox = nil }

    // MARK: - Outcome

    private func finishSession() {
        let heroChips = state.seat(heroSeatID)?.chips ?? 0
        let didWin = heroChips > 0
        outcome = didWin ? .won : .lost
        conductor.say(croupier: nil, synthesis: SpeechMap.text(for: didWin ? .sessionWon : .sessionLost))
    }

    // MARK: - Narration helpers

    /// Immediate VoiceOver feedback for the Raise box (D-027): interrupting so a
    /// burst of +/- taps collapses to the latest value. Not routed through the
    /// conductor — it's rapid UI feedback, not narrative, and no croupier voice
    /// plays while the box is open.
    private func announce(_ message: String, interrupting: Bool = false) {
        announcer.announce(message, interrupting: interrupting)
    }

    // MARK: - UI input sounds (played by the UI itself, not from the stream)

    /// Plays a UI-feedback sound for a direct user input (D-023: UI feedback is
    /// played directly, not via the event flow).
    private func playUI(_ id: SoundID) { audio.play(id, category: .ui) }

    // MARK: - Human rhythm

    private func pause(_ seconds: Double) async {
        let effective = fastMode ? 0.01 : seconds
        try? await Task.sleep(nanoseconds: UInt64(effective * 1_000_000_000))
    }
}
