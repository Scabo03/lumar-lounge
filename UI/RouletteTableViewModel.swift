// RouletteTableViewModel.swift
// =====================================================================
// Owns a roulette session and turns its code-speed event stream into a
// human-paced, observable table (D-103).
//
// It holds the ONE `RouletteBetSlip` (the single source of truth, D-102) that
// both zones — the selection table and the register band — edit through the SAME
// methods here. There is no bet logic in the views: they call `place`, `increase`,
// `decrease`, `remove` on this model, which forwards to the slip. Two interfaces,
// one state.
//
// It reuses the proven cross-cutting machinery: `AnnouncementQueue` +
// `SpeechConductor` for the one spoken channel (D-032/D-085), the app's VoiceOver
// mode for adaptive pacing (D-034), and the focus-landing discipline (D-092): after
// confirm and after the outcome, focus is placed on a live element, never left on a
// control that has changed under it.
//
// THE SPIN WAIT (D-103), the delicate point with no mp3 yet: the "no more bets"
// croupier cue (informative → synthesis fallback) fills the ear right after confirm,
// then a SHORT floor beat stands in for the wheel, so the interval is felt, not a
// silent freeze. The wait is sized to `audio.duration(of: wheel) ?? spinFloor`, so
// when the real wheel mp3 is cabled it simply governs the wait — the fill it replaces
// needs no dismantling.

import Foundation
import GameEngine
import GameWorld
import Audio

@MainActor
public final class RouletteTableViewModel: ObservableObject {

    @Published public private(set) var state: RouletteTableState
    /// THE single source of truth for the bets being composed (D-102).
    @Published public private(set) var slip: RouletteBetSlip
    /// Bumped on every phase transition so the status element re-claims focus (D-092).
    @Published public private(set) var focusToken = 0
    @Published public private(set) var outcome: GameOutcome?
    /// True only while the driver is actually waiting for this round's bets — so the
    /// spin can't be confirmed before the betting suspension exists (the initial phase
    /// is `.betting` for display, but no round is open until the driver asks).
    @Published public private(set) var awaitingBets = false

    public let returnLabel: String
    public let minimumBet: Int
    public let maximumBet: Int

    private let driver: RouletteSessionDriver
    private let human = HumanRouletteActionProvider()
    private let announcements = AnnouncementQueue()
    private let fastMode: Bool
    private let audio: AudioServicing
    private let conductor: SpeechConductor
    private let mode: AppVoiceOverMode
    private let casinoAudio: CasinoAudio
    private let onLeave: (Int) -> Void

    private var eventQueue: [RouletteEventPayload] = []
    private var streamFinished = false
    private var betContinuation: CheckedContinuation<Void, Never>?
    private var hasLeft = false
    private var leaveRequested = false

    public init(seed: UInt64? = nil,
                fastMode: Bool = false,
                audio: AudioServicing = NullAudioService(),
                mode: AppVoiceOverMode,
                rules: RouletteTableRules = .riverwood,
                returnLabel: String,
                casinoAudio: CasinoAudio = .riverwood,
                onLeave: @escaping (Int) -> Void = { _ in }) {
        self.fastMode = fastMode
        self.audio = audio
        self.mode = mode
        self.casinoAudio = casinoAudio
        self.returnLabel = returnLabel
        self.onLeave = onLeave
        self.minimumBet = rules.minimumBet
        self.maximumBet = rules.maximumBet

        self.driver = RouletteSessionDriver(chips: rules.buyIn, rules: rules,
                                            provider: human, seed: seed)
        self.conductor = SpeechConductor(audio: audio, queue: announcements)
        self.slip = RouletteBetSlip(minimumBet: rules.minimumBet, maximumBet: rules.maximumBet)
        self.state = RouletteTableState(chips: rules.buyIn,
                                        minimumBet: rules.minimumBet,
                                        maximumBet: rules.maximumBet)
    }

    // MARK: - Lifecycle

    public func run() async {
        let stream = await driver.events(as: .spectator)
        let beds = casinoAudio.ambient(forGame: "roulette")
        audio.startAmbient(audio.isAvailable(beds.calm1) ? beds.calm1 : beds.calm1Fallback)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.relay(stream) }
            group.addTask { await self.produce() }
            group.addTask { await self.consume() }
        }
    }

    private func relay(_ stream: AsyncStream<RouletteSessionEvent>) async {
        for await event in stream { eventQueue.append(event.payload) }
        streamFinished = true
    }

    private func produce() async {
        while !Task.isCancelled && driver.canSpinAgain {
            if leaveRequested { break }
            guard let _ = try? await driver.playRound() else { break }
            if leaveRequested { break }
        }
        await driver.endSession()
    }

    private func consume() async {
        while !Task.isCancelled, !hasLeft {
            if !eventQueue.isEmpty {
                await present(eventQueue.removeFirst())
            } else if await human.pending != nil {
                await runBetting()
            } else if streamFinished {
                break
            } else {
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        }
    }

    // MARK: - Presenting

    private func present(_ payload: RouletteEventPayload) async {
        switch payload {
        case .sessionBegan:
            state = RouletteTableReducer.reduce(state, payload)

        case .roundBegan:
            state = RouletteTableReducer.reduce(state, payload)
            // "Rien ne va plus" — the natural roulette call, and the audible signal that
            // the wheel is starting. Informative → the register/synthesis fallback speaks
            // it when the mp3 is absent (D-030), filling the ear after confirm.
            let (lead, fbKey) = casinoAudio.croupier(SoundCatalog.voRouletteNoMoreBets)
            conductor.say(lead: lead,
                          synthesis: nil,
                          fallback: fbKey.map(uiLocalized) ?? uiLocalized("roulette.no.more.bets"),
                          priority: .medium, reason: "roulette-spin-start")
            await pace(payload)

        case .wheelSpun:
            state = RouletteTableReducer.reduce(state, payload)
            // The wheel FILL. Silent today (a `.table` effect falls back to silence), so
            // the ear is held by the cue above and this short floor stands in for the
            // spin. When the mp3 is cabled its duration governs the wait — no teardown.
            audio.play(SoundCatalog.fxRouletteWheelSpin, category: .table)
            let spin = audio.duration(of: SoundCatalog.fxRouletteWheelSpin) ?? RoulettePacing.spinFloor
            await pause(spin)

        case let .roundResolved(resolution, _):
            state = RouletteTableReducer.reduce(state, payload)
            // The compact outcome (HIGH — it carries money, never dropped, D-085), with the
            // win/lose sting SEQUENCED AFTER it, so no sound anticipates the result (D-085).
            conductor.say(lead: nil,
                          synthesis: RouletteSpeechMap.outcomeLine(for: resolution),
                          trailing: sting(for: resolution),
                          priority: RouletteSpeechMap.outcomePriority,
                          reason: "roulette-outcome")
            focusToken += 1   // focus lands on the result element (D-092)
            await pace(payload)

        case .roundEnded:
            state = RouletteTableReducer.reduce(state, payload)
            await pace(payload)

        case .sessionEnded:
            state = RouletteTableReducer.reduce(state, payload)
            finishSession()
        }
    }

    private func sting(for r: RouletteRoundResolution) -> SoundID {
        r.net > 0 ? SoundCatalog.fxRouletteWin : (r.net < 0 ? SoundCatalog.fxRouletteLose : SoundCatalog.fxHandNeutral)
    }

    // MARK: - The betting suspension

    private func runBetting() async {
        if hasLeft { return }
        // A fresh composition each round.
        slip.clear()
        state.phase = .betting
        awaitingBets = true
        focusToken += 1   // focus lands on the status/total element (D-092)
        await withCheckedContinuation { betContinuation = $0 }
        awaitingBets = false
    }

    // MARK: - Pacing

    private func pace(_ payload: RouletteEventPayload) async {
        announcements.pacedWhenSilent = mode.isEnabled
        if mode.isEnabled { await awaitSpokenChannelQuiet() }
        else { await pause(RoulettePacing.seconds(for: payload)) }
    }

    private func awaitSpokenChannelQuiet() async {
        _ = await SpokenChannelPacing.awaitQuiet(
            isQuiet: { self.conductor.isIdle && self.announcements.isQuiet },
            isCancelled: { Task.isCancelled },
            maxWait: SpokenChannelPacing.adaptiveMaxWait(channelRemaining: self.conductor.channelRemaining),
            label: "roulette")
    }

    private func pause(_ seconds: Double) async {
        let effective = fastMode ? 0.01 : seconds
        try? await Task.sleep(nanoseconds: UInt64(effective * 1_000_000_000))
    }

    // MARK: - Bet editing — the ONE set of methods both zones call (D-102)

    public func placeMinimum(_ bet: RouletteBet) {
        slip.place(bet)
        playUI(SoundCatalog.fxRouletteChipPlace)
    }

    /// The sighted tap: place the minimum if empty, otherwise stack another minimum —
    /// the natural "keep dropping chips" gesture. Both branches call the slip.
    public func tapCell(_ bet: RouletteBet) {
        slip.increase(bet)
        playUI(SoundCatalog.fxRouletteChipPlace)
    }

    /// A swipe-up on a cell/symbol. The new amount is read by VoiceOver from the
    /// element's accessibilityValue (the standard adjustable behaviour) — the state is
    /// legible right where the swipe happens, exactly as the sighted player sees the
    /// fiches grow on the felt.
    public func increase(_ bet: RouletteBet) {
        slip.increase(bet)
        playUI(SoundCatalog.fxRouletteChipPlace)
    }

    /// A swipe-down: remove a minimum, and REMOVE the bet outright once it reaches zero
    /// (the symbol's way of being cancelled, D-102).
    public func decrease(_ bet: RouletteBet) {
        let removing = slip.amount(on: bet) <= slip.minimumBet
        slip.decrease(bet)
        playUI(removing ? SoundCatalog.fxRouletteChipRemove : SoundCatalog.fxRouletteChipPlace)
    }

    public func remove(_ bet: RouletteBet) {
        slip.remove(bet)
        playUI(SoundCatalog.fxRouletteChipRemove)
    }

    // MARK: - Confirm / leave

    public var canConfirm: Bool { awaitingBets && slip.totalStaked > 0 }

    public func confirm() {
        guard canConfirm, let continuation = betContinuation else { return }
        betContinuation = nil
        let bets = slip.bets
        state.phase = .spinning
        playUI(SoundCatalog.uiConfirm)
        Task {
            await human.submit(bets)
            continuation.resume()
        }
    }

    /// Leaving early: roulette is like blackjack — the player is alone against chance, so
    /// walking away simply cashes out the chips in hand (D-090). Any bets on the felt are
    /// forfeit, and that needs no special case: the chips were already deducted at
    /// confirm, so cashing out what is left IS the forfeit.
    public func requestLeave() {
        guard !hasLeft else { return }
        hasLeft = true
        leaveRequested = true
        let remaining = state.chips
        // Resume any suspended betting so the consume loop can wind up.
        if let continuation = betContinuation { betContinuation = nil; continuation.resume() }
        Task { await human.abandon() }
        onLeave(remaining)
    }

    public func returnToCasino() { onLeave(state.chips) }

    private func finishSession() {
        if leaveRequested { return }
        // A roulette session ends one way: the player can no longer cover the minimum.
        outcome = .lost
        conductor.say(lead: nil,
                      synthesis: uiLocalized("roulette.session.broke"),
                      priority: .high, reason: "session-end")
    }

    private func playUI(_ id: SoundID) { audio.play(id, category: .ui) }
}
