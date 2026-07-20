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
    // Internal (not private) so a measurement can observe the spoken channel — the
    // one thing that cannot be checked any other way (D-098).
    let announcements = AnnouncementQueue()
    private let gate = HandGate()
    private let fastMode: Bool
    private let audio: AudioServicing
    private let audioDirector: BlackjackAudioDirector
    let conductor: SpeechConductor

    /// Estimated seconds of speech the whole spoken channel still owes, right now.
    /// A measurement samples this at the instant the wager box opens: if it is not
    /// ~zero, the box is interrupting the round's own explanation (D-098).
    var spokenChannelRemaining: TimeInterval {
        conductor.channelRemaining + announcements.estimatedRemaining
    }
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
    /// Whether the dealer's total has been said this round, so the combined
    /// end-of-hand line names it once even across a split (D-098).
    private var dealerClauseSaid = false

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
            dealerClauseSaid = false
            state = BlackjackTableReducer.reduce(state, payload)
            await pace(payload)

        case let .dealt(_, _, _, dealerUpCard, _):
            // TWO BEATS, not one (D-096/D-097). Everything used to land at once:
            // the hand appeared, VoiceOver focus landed on it and began reading
            // total and cards, and the deal announcement fired on top — so the
            // two talked over each other and the player had to swipe back to the
            // hand to hear the amount. Now the hand arrives ALONE and is read in
            // full; the dealer's card is turned only once that read is expected
            // to have finished (estimated from the hand line, D-097), into a
            // channel nobody else is using.
            state = BlackjackTableReducer.reduce(state, payload)
            state.dealerCards = []
            if isListening, let hand = state.hands.first {
                // The focus-landing read is the TOTAL only (D-098) — short — so the
                // wait is short and the dealer follows promptly, without ever
                // cutting the read off partway through the cards.
                let read = BlackjackReadout.total(hand, index: 0, handCount: state.hands.count)
                await pause(BlackjackPacing.dealerRevealDelay(afterReading: read))
            }
            guard !hasLeft else { return }
            state.dealerCards = [dealerUpCard]
            speak(payload)
            await pace(payload)

        case let .handSettled(index, handCount, settledOutcome, _, bet, net):
            state = BlackjackTableReducer.reduce(state, payload)
            // ONE atomic end-of-hand line: WHY (the dealer) and WHAT (your
            // result), built together so nothing can split them and the whole
            // rapid account is heard as a unit (D-098). The dealer clause is said
            // once per round; a split's later hands add only their result.
            let cause = dealerClauseSaid ? nil : BlackjackSpeechMap.dealerClauseText(
                revealed: !state.holeCardHidden,
                total: state.dealerTotal,
                isSoft: BlackjackValue.total(state.dealerCards).isSoft,
                busted: state.dealerBusted,
                natural: state.dealerHasNatural)
            dealerClauseSaid = true
            let result = BlackjackSpeechMap.text(for: .settled(
                index: index, handCount: handCount, outcome: settledOutcome,
                amount: BlackjackSpeechMap.settlementAmount(settledOutcome, bet: bet, net: net)))
            let line = [cause, result].compactMap { $0 }.joined(separator: " ")
            // The sting that reveals the result is SEQUENCED behind the line that
            // explains it, never in parallel, so it cannot spoil the outcome (D-085).
            conductor.say(lead: nil, synthesis: line,
                          trailing: sting(for: settledOutcome),
                          priority: .high, reason: "bj-settle")
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

    /// Whether anyone is actually hearing the spoken channel — iOS VoiceOver is
    /// running, or the app's own VoiceOver mode is on. The accessibility beats
    /// (D-097) apply only then: a fully sighted player sees the hand and the
    /// dealer at once and must not be made to sit through pauses meant for the ear.
    private var isListening: Bool {
        forceListeningForTests || mode.isEnabled || announcements.isVoiceOverRunning
    }

    /// A measurement can force the listening path on, since no VoiceOver runs under
    /// test and the end-of-round waiting must still be exercised (D-098).
    var forceListeningForTests = false

    private func pause(_ seconds: Double) async {
        let effective = fastMode ? 0.01 : seconds
        try? await Task.sleep(nanoseconds: UInt64(effective * 1_000_000_000))
    }

    // MARK: - The two human suspensions

    private func runBet(_ context: BlackjackBetContext) async {
        if hasLeft { return }
        // THE ROUND MUST BE ALLOWED TO FINISH BEING EXPLAINED (D-096/D-097).
        // The wager box lands VoiceOver focus, and focus landing posts a
        // notification that INTERRUPTS whatever is being spoken. Every round
        // ended the same way: the dealer's total and the settlement line were
        // cut off by the next box, leaving the player with a win/lose sting and
        // no account of what had happened. So, only while someone is listening:
        // a floor beat first, so a just-enqueued settlement is actually in
        // flight and being heard, THEN wait for the whole channel to fall quiet
        // so the box never opens over it. Both cost a sighted player nothing.
        if isListening {
            await pause(BlackjackPacing.betBoxLeadIn)
            await awaitSpokenChannelQuiet()
        }
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
