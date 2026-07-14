// StudTableViewModel.swift
// =====================================================================
// Owns the ClockTower's Seven-Card Stud Pot Limit session (human + two of the tower's
// regulars), turns its code-speed event stream into a human-paced, observable
// `StudTableState`, narrates it to VoiceOver, and drives the human's ONE decision point:
// a betting turn (fold/check/call, and a Pot-Limit raise box). It forwards the chosen
// action to the `HumanStudActionProvider` (D-077).
//
// It reuses the proven synchronisation shape (D-021): the stream is relayed into a
// MainActor queue; the action bar / raise box appear when the paced display has caught up
// to the human's decision point (the provider is waiting). It reuses the shared spoken
// channel (`SpeechConductor` + `AnnouncementQueue`) and the app's VoiceOver mode for
// adaptive pacing (D-034). It narrates the HOUSE PRIZE (D-078). No game logic here.
//
// POT LIMIT (D-077): the raise box maximum is the cap the engine reports, which may be
// BELOW the stack — so "there is no all-in shove" when the stack exceeds the pot. The
// box's max button is "All-in" only when the max actually reaches the stack; otherwise
// "Pot" (reusing the Omaha box behaviour, D-066).

import Foundation
import GameWorld
import GameEngine
import Audio

/// The information the action bar + raise box need on the human's betting turn.
public struct StudTurnInfo: Equatable, Sendable {
    public let toCall: Int
    public let potSize: Int
    public let heroStack: Int
    public let currentBet: Int
    public let canFold: Bool
    public let canCheck: Bool
    public let canCall: Bool
    public let callAmount: Int
    public let canBetOrRaise: Bool
    public let isBet: Bool
    public let minTo: Int
    public let maxTo: Int
    /// Whether betting to `maxTo` actually puts the hero all-in. When false, the max is the
    /// POT and no shove is possible — the Pot-Limit distinction.
    public let canShove: Bool

    init(from context: StudBotContext) {
        let legal = context.legal
        toCall = context.toCall
        potSize = context.potSize
        heroStack = context.heroStack
        currentBet = context.currentBet
        canFold = legal.canFold
        canCheck = legal.canCheck
        canCall = legal.canCall
        callAmount = legal.callAmount
        if legal.canBet {
            canBetOrRaise = true; isBet = true; minTo = legal.minBetTo; maxTo = legal.maxBetTo
        } else if legal.canRaise {
            canBetOrRaise = true; isBet = false; minTo = legal.minRaiseTo; maxTo = legal.maxRaiseTo
        } else {
            canBetOrRaise = false; isBet = false; minTo = 0; maxTo = 0
        }
        let allInTo = (context.currentBet - context.toCall) + context.heroStack
        canShove = canBetOrRaise && maxTo >= allInTo
    }
}

@MainActor
public final class StudTableViewModel: ObservableObject {

    @Published public private(set) var state: StudTableState
    @Published public private(set) var humanTurn: StudTurnInfo?
    @Published public private(set) var raiseBox: RaiseBoxState?
    @Published public private(set) var outcome: GameOutcome?
    @Published public private(set) var pendingLeave = false

    public let names: [Int: String]
    public let heroSeatID = 0
    public let returnLabel: String

    private let driver: StudSessionDriver
    private let human = HumanStudActionProvider()
    private let announcements = AnnouncementQueue()
    private let gate = HandGate()
    private let fastMode: Bool
    private let audio: AudioServicing
    private let audioDirector: StudAudioDirector
    private let conductor: SpeechConductor
    private let mode: AppVoiceOverMode
    private let casinoAudio: CasinoAudio
    private let onLeave: (Int) -> Void
    /// The House Prize amount, paid ONLY at cash-out on a full-table win (D-079). The
    /// driver/table never sees it.
    private let housePrize: Int

    private var leaveAfterHand = false
    private var eventQueue: [StudEventPayload] = []
    private var streamFinished = false
    private var turnContinuation: CheckedContinuation<Void, Never>?
    private var shownCategory: [Int: HandCategory] = [:]
    private var shownBestFive: [Int: [Card]] = [:]
    private var potAnnounced = false
    private var raiseTurn: StudTurnInfo?

    /// - Parameter seed: `nil` (production) → fresh RANDOM cards every hand (D-047); a
    ///   fixed value makes the whole session deterministic (tests/previews).
    public init(seed: UInt64? = nil, fastMode: Bool = false,
                audio: AudioServicing = NullAudioService(),
                mode: AppVoiceOverMode,
                rules: StudTableRules = .clockTower,
                returnLabel: String,
                casinoAudio: CasinoAudio = .clockTower,
                onLeave: @escaping (Int) -> Void = { _ in }) {
        self.fastMode = fastMode
        self.audio = audio
        self.mode = mode
        self.returnLabel = returnLabel
        self.casinoAudio = casinoAudio
        self.onLeave = onLeave
        self.housePrize = rules.housePrize

        let rootSeed = seed ?? UInt64.random(in: .min ... .max)
        let startingChips = rules.buyIn
        let nameKeys = ["seat.name.clock.student", "seat.name.clock.professor"]
        let bots = zip(1...rules.personalities.count, rules.personalities).map { (id: $0.0, personality: $0.1) }
        var assignments = [StudSeatAssignment(position: 0, playerID: 0, chips: startingChips, provider: human)]
        assignments += bots.map { bot in
            StudSeatAssignment(position: bot.id, playerID: bot.id, chips: startingChips,
                               provider: StudBotActionProvider(HeuristicStudBot(personality: bot.personality,
                                                                                seed: UInt64(bot.id) * 101 &+ rootSeed)))
        }
        self.driver = StudSessionDriver(capacity: bots.count + 1, seats: assignments,
                                        ante: rules.ante, bringIn: rules.bringIn, bet: rules.bet,
                                        seed: seed, escalation: rules.escalation)

        var names = [0: uiLocalized("seat.name.you")]
        for (bot, key) in zip(bots, nameKeys) { names[bot.id] = uiLocalized(key) }
        self.names = names

        self.audioDirector = StudAudioDirector(audio: audio, heroSeatID: 0, fastMode: fastMode,
                                               seed: rootSeed, ambient: casinoAudio.ambient)
        self.conductor = SpeechConductor(audio: audio, queue: announcements)

        self.state = StudTableState(
            seats: ([0] + bots.map { $0.id }).map { StudSeatPresentation(id: $0, position: $0, chips: startingChips) },
            ante: rules.ante, bringIn: rules.bringIn, bet: rules.bet, heroSeatID: 0)
    }

    // MARK: - Leaving

    public func requestLeave() {
        if outcome != nil { onLeave(heroCashOut); return }
        leaveAfterHand = true
        pendingLeave = true
    }

    // MARK: - Lifecycle

    public func run() async {
        let display = await driver.events(as: .player(heroSeatID))
        let audioStream = await driver.events(as: .spectator)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.relay(display) }
            group.addTask { await self.produce() }
            group.addTask { await self.consume() }
            group.addTask { await self.audioDirector.run(audioStream) }
        }
    }

    private func relay(_ stream: AsyncStream<StudSessionEvent>) async {
        for await event in stream { eventQueue.append(event.payload) }
        streamFinished = true
    }

    private func produce() async {
        while !Task.isCancelled && driver.canDealNextHand {
            await gate.acquire()
            if Task.isCancelled || leaveAfterHand { break }
            _ = try? await driver.playHand()
            if leaveAfterHand { break }
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
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        }
    }

    // MARK: - Presenting events (human paced)

    private func present(_ payload: StudEventPayload) async {
        switch payload {
        case .handBegan:
            conductor.handBegan()
            shownCategory.removeAll()
            shownBestFive.removeAll()
            potAnnounced = false
            state = StudTableReducer.reduce(state, payload)
            speak(payload, "hand-start")
            await pace(payload)

        case let .streetBegan(street) where street != .third:
            state = StudTableReducer.reduce(state, payload)
            speak(payload, "street")
            await pace(payload)

        case let .upCardDealt(_, _, street):
            state = StudTableReducer.reduce(state, payload)
            speak(payload, "upcard")
            // First deal (third street) is quick; later reveals are a beat slower.
            await pace(payload, override: street == .third ? 0.35 : nil)

        case let .privateDownCards(seatID, _) where seatID == heroSeatID:
            state = StudTableReducer.reduce(state, payload)
            speak(payload, "hero-cards")
            await pace(payload)

        case .bringInPosted:
            state = StudTableReducer.reduce(state, payload)
            speak(payload, "bring-in")
            await pace(payload)

        case let .playerActed(seatID, action):
            state.activeSeatID = seatID
            if seatID != heroSeatID { await pause(mode.isEnabled ? 0.1 : 0.5) }
            state = StudTableReducer.reduce(state, payload)
            speakAction(seatID: seatID, action: action)
            await pace(payload)
            if state.activeSeatID == seatID { state.activeSeatID = nil }

        case let .handShown(seatID, _, category, bestFive):
            shownCategory[seatID] = category
            shownBestFive[seatID] = bestFive
            state = StudTableReducer.reduce(state, payload)
            speak(payload, "showdown")
            await pace(payload)

        case .potAwarded:
            state = StudTableReducer.reduce(state, payload)
            speakPot(payload)
            await pace(payload)

        case .handEnded:
            state = StudTableReducer.reduce(state, payload)
            await gate.release()
            await pace(payload)

        case .sessionEnded:
            state = StudTableReducer.reduce(state, payload)
            finishSession()

        default:
            state = StudTableReducer.reduce(state, payload)
            await pace(payload)
        }
    }

    private func pace(_ payload: StudEventPayload, override: Double? = nil) async {
        announcements.pacedWhenSilent = mode.isEnabled
        if mode.isEnabled { await awaitSpokenChannelQuiet() }
        else { await pause(override ?? StudPacing.seconds(for: payload)) }
    }

    private func awaitSpokenChannelQuiet() async {
        SpokenLog.log("visual WAIT begin (stud)")
        let quiet = await SpokenChannelPacing.awaitQuiet(
            isQuiet: { self.conductor.isIdle && self.announcements.isQuiet },
            isCancelled: { Task.isCancelled },
            label: "stud")
        SpokenLog.log("visual WAIT end (stud) quiet=\(quiet)")
    }

    // MARK: - Speech

    private func speak(_ payload: StudEventPayload, _ reason: String = "") {
        say(StudSpeechMap.plan(for: payload, heroSeatID: heroSeatID, names: names), reason: reason)
    }

    /// Sends a plan to the conductor, resolving the croupier LEAD + register fallback
    /// through the HOSTING CASINO's palette (D-067) — the ClockTower custode here.
    private func say(_ plan: StudSpeechPlan, reason: String) {
        let (lead, fbKey) = casinoAudio.croupier(plan.croupier)
        let fallback = fbKey.map(uiLocalized) ?? plan.croupierFallback.map(StudSpeechMap.text)
        conductor.say(lead: lead, synthesis: plan.synthesis.map(StudSpeechMap.text),
                      fallback: fallback, priority: priority(of: plan), reason: reason)
    }

    private func speakAction(seatID: Int, action: StudActedAction) {
        let plan = StudSpeechMap.plan(for: .playerActed(seatID: seatID, action: action),
                                      heroSeatID: heroSeatID, names: names)
        let synth = plan.synthesis.map(StudSpeechMap.text)
        if plan.croupier != nil {
            let (lead, fbKey) = casinoAudio.croupier(plan.croupier)
            conductor.say(lead: lead, synthesis: synth,
                          fallback: fbKey.map(uiLocalized) ?? plan.croupierFallback.map(StudSpeechMap.text),
                          priority: .medium, reason: "action-allin")
        } else if let synth {
            conductor.say(lead: nil, synthesis: synth, priority: .medium, reason: "opp-action")
        }
    }

    private func priority(of plan: StudSpeechPlan) -> AnnouncementPriority {
        if let s = plan.synthesis { return StudSpeechMap.priority(for: s) }
        if let f = plan.croupierFallback { return StudSpeechMap.priority(for: f) }
        return .medium
    }

    private func speakPot(_ payload: StudEventPayload) {
        guard case let .potAwarded(_, _, winners) = payload, !potAnnounced else { return }
        potAnnounced = true
        let plan = StudSpeechMap.plan(for: payload, heroSeatID: heroSeatID, names: names)
        let joined = winners.map { names[$0] ?? "\($0)" }.joined(separator: ", ")
        let ref = winners.first
        let line: StudSynthLine?
        if winners.count > 1 {
            line = .splitWon(who: joined, category: ref.flatMap { shownCategory[$0] },
                             bestFive: ref.flatMap { shownBestFive[$0] })
        } else if winners.contains(heroSeatID) {
            line = .heroWon(category: shownCategory[heroSeatID], bestFive: shownBestFive[heroSeatID])
        } else if let winner = winners.first {
            line = .otherWon(who: names[winner] ?? "\(winner)",
                             category: shownCategory[winner], bestFive: shownBestFive[winner])
        } else {
            line = nil
        }
        let prio = line.map(StudSpeechMap.priority) ?? .high
        let (lead, _) = casinoAudio.croupier(plan.croupier)
        conductor.say(lead: lead, synthesis: line.map(StudSpeechMap.text), priority: prio, reason: "pot")
    }

    // MARK: - The human's betting turn

    private func runHumanTurn(_ context: StudBotContext) async {
        let info = StudTurnInfo(from: context)
        humanTurn = info
        state.activeSeatID = heroSeatID
        conductor.flushPending()
        // No tower "your turn" mp3 was delivered → the synthesis "A te la parola" speaks it
        // (kept as an ESSENTIAL turn signal for the blind player, D-080).
        let (lead, fbKey) = casinoAudio.croupier(SoundCatalog.voTowerYourTurn)
        conductor.say(lead: lead, synthesis: nil,
                      fallback: fbKey.map(uiLocalized) ?? uiLocalized("stud.announce.yourturn"),
                      priority: .high, reason: "your-turn")
        await withCheckedContinuation { turnContinuation = $0 }
        humanTurn = nil
        raiseBox = nil
        if state.activeSeatID == heroSeatID { state.activeSeatID = nil }
    }

    private func act(_ action: StudAction) {
        guard let continuation = turnContinuation else { return }
        turnContinuation = nil
        humanTurn = nil
        raiseBox = nil
        Task {
            await human.submit(action)
            continuation.resume()
        }
    }

    // MARK: - Action-bar + raise-box intents (called by the view)

    public func fold() { playUI(SoundCatalog.uiButtonTap); act(.fold) }

    public func checkOrCall() {
        guard let turn = humanTurn else { return }
        playUI(SoundCatalog.uiButtonTap)
        act(turn.canCheck ? .check : .call)
    }

    public func openRaiseBox() {
        guard let turn = humanTurn, turn.canBetOrRaise else { return }
        playUI(SoundCatalog.uiBoxOpen)
        raiseTurn = turn
        raiseBox = RaiseBoxState(minTo: turn.minTo, maxTo: turn.maxTo, isBet: turn.isBet)
    }

    public var raiseCanShove: Bool { raiseTurn?.canShove ?? false }
    public var raiseCapTo: Int { raiseTurn?.maxTo ?? 0 }

    public func raisePlus() {
        guard var box = raiseBox else { return }
        playUI(SoundCatalog.uiRaisePlus)
        box.increase(); raiseBox = box
        announceRaiseValue(box)
    }

    public func raiseMinus() {
        guard var box = raiseBox else { return }
        playUI(SoundCatalog.uiRaiseMinus)
        box.decrease(); raiseBox = box
        announceRaiseValue(box)
    }

    public func raiseMax() {
        guard var box = raiseBox else { return }
        playUI(SoundCatalog.uiAllInTrigger)
        box.toMax(); raiseBox = box
        announceRaiseValue(box)
    }

    private func announceRaiseValue(_ box: RaiseBoxState) {
        if box.isAtMax && !raiseCanShove {
            announcements.announceLiveValue(uiLocalized("omaha.raise.cap.a11y", box.value))
        } else {
            announcements.announceLiveValue(uiLocalized("omaha.raise.value.a11y", box.value))
        }
    }

    public func confirmRaise() {
        guard let box = raiseBox else { return }
        playUI(SoundCatalog.uiConfirm)
        act(box.isBet ? .bet(box.value) : .raise(box.value))
    }

    public func cancelRaise() { playUI(SoundCatalog.uiBoxClose); raiseBox = nil }

    // MARK: - Outcome & the House Prize (D-079)

    /// Whether the player BEAT THE TABLE: they still have chips and both opponents are out.
    private var beatTheTable: Bool {
        HousePrize.beatTheTable(heroChips: state.seat(heroSeatID)?.chips ?? 0,
                                opponentChips: state.opponents.map { $0.chips })
    }

    /// The chips to cash out: the hero's remaining table chips PLUS the House Prize, but
    /// ONLY on a full-table win (D-079). This is the sole place the prize enters the
    /// economy — a GameWorld pure function at the persistent-chips boundary; no table stack
    /// is ever touched.
    private var heroCashOut: Int {
        HousePrize.cashOut(heroChips: state.seat(heroSeatID)?.chips ?? 0,
                           opponentChips: state.opponents.map { $0.chips }, prize: housePrize)
    }

    private func finishSession() {
        let heroChips = state.seat(heroSeatID)?.chips ?? 0
        if leaveAfterHand { onLeave(heroCashOut); return }
        let didWin = heroChips > 0
        outcome = didWin ? .won : .lost
        // On a full-table win, the custode announces the House Prize (no mp3 delivered → the
        // synthesis speaks the reward, D-079/D-080), spoken once, at the end.
        if beatTheTable, housePrize > 0 {
            let (lead, fbKey) = casinoAudio.croupier(SoundCatalog.voTowerHousePrize)
            conductor.say(lead: lead, synthesis: StudSpeechMap.text(for: .housePrize(amount: housePrize)),
                          fallback: fbKey.map(uiLocalized), priority: .high, reason: "house-prize")
        }
        // The custode's end-of-game flourish (mp3 delivered) leads the win/lose line.
        let (endLead, _) = casinoAudio.croupier(SoundCatalog.voTowerGameEnd)
        conductor.say(lead: endLead, synthesis: StudSpeechMap.text(for: didWin ? .sessionWon : .sessionLost),
                      priority: .high, reason: "session-end")
    }

    public func returnToCasino() { onLeave(heroCashOut) }

    // MARK: - Helpers

    private func playUI(_ id: SoundID) { audio.play(id, category: .ui) }

    private func pause(_ seconds: Double) async {
        let effective = fastMode ? 0.01 : seconds
        try? await Task.sleep(nanoseconds: UInt64(effective * 1_000_000_000))
    }
}
