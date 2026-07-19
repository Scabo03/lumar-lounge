// BlackjackTableViewModel.swift
// =====================================================================
// Drains the blackjack event stream at a human rhythm, drives the two human
// suspensions (the wager, then the moves), and owns the spoken channel for
// the table.
//
// Same skeleton as the poker tables — relay / produce / consume, HandGate,
// AnnouncementQueue + SpeechConductor, adaptive pacing when the app's
// VoiceOver mode is on — because the producer must stay ignorant of the human
// rhythm (D-018) and all the cross-cutting work on channel budget and
// synchronisation (D-085) must be respected, not re-invented.

import Foundation
import GameEngine
import GameWorld
import Audio

@MainActor
public final class BlackjackTableViewModel: ObservableObject {

    @Published public private(set) var state: BlackjackTableState
    @Published public private(set) var turn: BlackjackTurnContext?
    @Published public private(set) var betBox: BlackjackBetBox?
    @Published public private(set) var outcome: GameOutcome?

    public let returnLabel: String
    public let minimumBet: Int
    public let maximumBet: Int

    private let driver: BlackjackSessionDriver
    private let human = HumanBlackjackActionProvider()
    private let announcements = AnnouncementQueue()
    private let gate = HandGate()
    private let fastMode: Bool
    private let audio: AudioServicing
    private let audioDirector: BlackjackAudioDirector
    private let conductor: SpeechConductor
    private let mode: AppVoiceOverMode
    private let casinoAudio: CasinoAudio
    private let onLeave: (Int) -> Void

    private var eventQueue: [BlackjackEventPayload] = []
    private var streamFinished = false
    private var turnContinuation: CheckedContinuation<Void, Never>?
    private var betContinuation: CheckedContinuation<Void, Never>?
    private var leaveRequested = false
    private var hasLeft = false
    private var lastBet: Int?

    public init(seed: UInt64? = nil,
                fastMode: Bool = false,
                audio: AudioServicing = NullAudioService(),
                mode: AppVoiceOverMode,
                rules: BlackjackTableRules = .riverwood,
                returnLabel: String,
                casinoAudio: CasinoAudio = .riverwood,
                onLeave: @escaping (Int) -> Void = { _ in }) {
        // D-047: a fixed seed in tests, a genuinely random one in production.
        let rootSeed = seed ?? UInt64.random(in: .min ... .max)

        self.fastMode = fastMode
        self.audio = audio
        self.mode = mode
        self.casinoAudio = casinoAudio
        self.returnLabel = returnLabel
        self.onLeave = onLeave
        self.minimumBet = rules.minimumBet
        self.maximumBet = rules.maximumBet

        self.driver = BlackjackSessionDriver(chips: rules.buyIn,
                                             rules: rules,
                                             provider: human,
                                             seed: seed)
        self.audioDirector = BlackjackAudioDirector(audio: audio,
                                                    fastMode: fastMode,
                                                    seed: rootSeed,
                                                    ambient: casinoAudio.ambient(forGame: "blackjack"))
        self.conductor = SpeechConductor(audio: audio, queue: announcements)

        // Seeded synchronously so the first frame is never empty.
        self.state = BlackjackTableState(chips: rules.buyIn,
                                         minimumBet: rules.minimumBet,
                                         maximumBet: rules.maximumBet)
    }

    // MARK: - Lifecycle

    public func run() async {
        let display = await driver.events(as: .spectator)
        let audioStream = await driver.events(as: .spectator)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.relay(display) }
            group.addTask { await self.produce() }
            group.addTask { await self.consume() }
            group.addTask { await self.audioDirector.run(audioStream) }
        }
    }

    private func relay(_ stream: AsyncStream<BlackjackSessionEvent>) async {
        for await event in stream {
            eventQueue.append(event.payload)
        }
        streamFinished = true
    }

    private func produce() async {
        while !Task.isCancelled && driver.canDealNextRound {
            await gate.acquire()
            if Task.isCancelled || leaveRequested { break }
            guard let _ = try? await driver.playRound() else { break }
            if leaveRequested { break }
        }
        await driver.endSession()
    }

    private func consume() async {
        while !Task.isCancelled, !hasLeft {
            if !eventQueue.isEmpty {
                await present(eventQueue.removeFirst())
            } else if let context = await human.pendingTurn {
                await runTurn(context)
            } else if let context = await human.pendingBet {
                await runBet(context)
            } else if streamFinished {
                break
            } else {
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        }
    }

    // MARK: - Presenting

    private func present(_ payload: BlackjackEventPayload) async {
        switch payload {
        case .roundBegan:
            conductor.handBegan()
            state = BlackjackTableReducer.reduce(state, payload)
            await pace(payload)

        case let .handSettled(_, _, settledOutcome, _, _, _):
            state = BlackjackTableReducer.reduce(state, payload)
            // The sting that reveals the result is SEQUENCED behind the line
            // that explains it, never fired in parallel — otherwise it spoils
            // the outcome before the player is told (D-085).
            speak(payload, trailing: sting(for: settledOutcome))
            await pace(payload)

        case .roundEnded:
            state = BlackjackTableReducer.reduce(state, payload)
            speak(payload)
            await gate.release()
            await pace(payload)

        case .sessionEnded:
            state = BlackjackTableReducer.reduce(state, payload)
            finishSession()

        default:
            state = BlackjackTableReducer.reduce(state, payload)
            speak(payload)
            await pace(payload)
        }
    }

    private func sting(for outcome: BlackjackOutcome) -> SoundID {
        switch outcome {
        case .natural, .win:          return SoundCatalog.fxWinHand
        case .push:                   return SoundCatalog.fxHandNeutral
        case .lose, .bust, .surrender: return SoundCatalog.fxLoseHand
        }
    }

    // MARK: - Speaking

    private func speak(_ payload: BlackjackEventPayload, trailing: SoundID? = nil) {
        let plan = BlackjackSpeechMap.plan(for: payload)
        guard plan.croupier != nil || plan.synthesis != nil || plan.croupierFallback != nil
                || trailing != nil else { return }

        // The casino-palette resolution idiom (D-067): the croupier and its
        // register fallback both come from the place, not from the game.
        let (lead, fallbackKey) = casinoAudio.croupier(plan.croupier)
        let fallback = fallbackKey.map(uiLocalized) ?? plan.croupierFallback.map { BlackjackSpeechMap.text(for: $0) }

        conductor.say(lead: lead,
                      synthesis: plan.synthesis.map { BlackjackSpeechMap.text(for: $0) },
                      fallback: fallback,
                      trailing: trailing,
                      priority: plan.synthesis.map(BlackjackSpeechMap.priority) ?? .medium,
                      reason: "blackjack")
    }

    // MARK: - Pacing

    private func pace(_ payload: BlackjackEventPayload) async {
        announcements.pacedWhenSilent = mode.isEnabled
        if mode.isEnabled {
            await awaitSpokenChannelQuiet()
        } else {
            await pause(BlackjackPacing.seconds(for: payload))
        }
    }

    private func awaitSpokenChannelQuiet() async {
        _ = await SpokenChannelPacing.awaitQuiet(
            isQuiet: { self.conductor.isIdle && self.announcements.isQuiet },
            isCancelled: { Task.isCancelled },
            maxWait: SpokenChannelPacing.adaptiveMaxWait(channelRemaining: self.conductor.channelRemaining),
            label: "blackjack")
    }

    private func pause(_ seconds: Double) async {
        let effective = fastMode ? 0.01 : seconds
        try? await Task.sleep(nanoseconds: UInt64(effective * 1_000_000_000))
    }

    // MARK: - The two human suspensions

    private func runBet(_ context: BlackjackBetContext) async {
        if hasLeft { return }
        betBox = BlackjackBetBox(minimum: context.minimumBet,
                                 maximum: min(context.maximumBet, context.chips),
                                 opening: context.lastBet)
        await withCheckedContinuation { betContinuation = $0 }
        betBox = nil
    }

    private func runTurn(_ context: BlackjackTurnContext) async {
        if hasLeft { return }
        turn = context
        state.activeHandIndex = context.handIndex
        // A time-critical prompt must not queue behind stale narration.
        conductor.flushPending()
        await withCheckedContinuation { turnContinuation = $0 }
        turn = nil
    }

    // MARK: - Intents

    public func betPlus() {
        guard var box = betBox else { return }
        box.increase()
        betBox = box
        playUI(SoundCatalog.uiRaisePlus)
        announceBetValue(box)
    }

    public func betMinus() {
        guard var box = betBox else { return }
        box.decrease()
        betBox = box
        playUI(SoundCatalog.uiRaiseMinus)
        announceBetValue(box)
    }

    public func betMax() {
        guard var box = betBox else { return }
        box.toMax()
        betBox = box
        playUI(SoundCatalog.uiAllInTrigger)
        announceBetValue(box)
    }

    public func confirmBet() {
        guard let box = betBox, let continuation = betContinuation else { return }
        betContinuation = nil
        betBox = nil
        lastBet = box.value
        playUI(SoundCatalog.uiConfirm)
        Task {
            await human.submitBet(box.value)
            continuation.resume()
        }
    }

    public func hit()       { act(.hit) }
    public func stand()     { act(.stand) }
    public func double()    { act(.double) }
    public func split()     { act(.split) }
    public func surrender() { act(.surrender) }

    private func act(_ action: BlackjackAction) {
        guard let continuation = turnContinuation else { return }
        turnContinuation = nil
        turn = nil
        playUI(SoundCatalog.uiButtonTap)
        Task {
            await human.submitAction(action)
            continuation.resume()
        }
    }

    private func announceBetValue(_ box: BlackjackBetBox) {
        // The one deliberate interruption (D-020): a burst of taps announces
        // only the last value instead of queueing up.
        announcements.announceLiveValue(uiLocalized("blackjack.bet.value.a11y", box.value))
    }

    private func playUI(_ id: SoundID) { audio.play(id, category: .ui) }

    // MARK: - Leaving (D-086)

    /// Leaving is a DECISION, not a request: it takes effect at once, with the
    /// natural cost of abandoning. Any wager already on the felt is forfeited —
    /// and that needs no special case, because the wager has ALREADY left the
    /// player's fiches, so cashing out what is left IS the forfeit.
    public func requestLeave() {
        guard !hasLeft else { return }
        hasLeft = true
        leaveRequested = true
        let remaining = state.chips
        Task { await human.abandon() }
        onLeave(remaining)
    }

    public func returnToCasino() {
        onLeave(state.chips)
    }

    private func finishSession() {
        if leaveRequested { return }
        // A blackjack session ends one way: the player can no longer cover the
        // table minimum. There is no table to beat and so no victory overlay
        // to earn — winning is simply walking away richer.
        outcome = .lost
        conductor.say(lead: nil,
                      synthesis: BlackjackSpeechMap.text(for: .sessionLost),
                      priority: .high,
                      reason: "session-end")
    }
}
