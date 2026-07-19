// OmahaTableViewModel.swift
// =====================================================================
// Owns the Skypool's Omaha Pot Limit session (human + three urban bots), turns its
// code-speed event stream into a human-paced, observable `OmahaTableState`, narrates
// it to VoiceOver, and drives the human's ONE decision point: a betting turn
// (fold/check/call, and a Pot-Limit raise box). It forwards the chosen action to the
// `HumanOmahaActionProvider` (D-066).
//
// It reuses the Texas synchronisation shape (D-021): the stream is relayed into a
// MainActor queue; the action bar / raise box appear when the paced display has caught
// up to the human's decision point (the provider is waiting). It reuses the shared
// spoken channel (`SpeechConductor` + `AnnouncementQueue`) and the app's VoiceOver
// mode for adaptive pacing (D-034). No game logic here.
//
// POT LIMIT (D-066): the raise box maximum is the POT-LIMIT cap the engine reports,
// which may be BELOW the whole stack — so "there is no all-in shove" when the stack
// exceeds the pot. The box's max button is "All-in" only when the max actually reaches
// the stack; otherwise it is "Pot", and both the caption and a VoiceOver cue say so.

import Foundation
import GameWorld
import GameEngine
import Audio

/// The information the action bar + raise box need on the human's betting turn.
public struct OmahaTurnInfo: Equatable, Sendable {
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
    /// Whether betting to `maxTo` actually puts the hero all-in (stack ≤ pot cap). When
    /// false, the max is the POT and no shove is possible — the Pot-Limit distinction.
    public let canShove: Bool

    init(from context: OmahaBotContext) {
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
        // heroStreetBet = currentBet - toCall; the all-in "to" = streetBet + stack.
        let allInTo = (context.currentBet - context.toCall) + context.heroStack
        canShove = canBetOrRaise && maxTo >= allInTo
    }
}

@MainActor
public final class OmahaTableViewModel: ObservableObject {

    @Published public private(set) var state: OmahaTableState
    /// Non-nil while it's the human's betting turn (the action buttons are active).
    @Published public private(set) var humanTurn: OmahaTurnInfo?
    /// Non-nil while the Pot-Limit raise box is open.
    @Published public private(set) var raiseBox: RaiseBoxState?
    @Published public private(set) var outcome: GameOutcome?
    @Published public private(set) var pendingLeave = false

    public let names: [Int: String]
    public let heroSeatID = 0
    public let returnLabel: String

    private let driver: OmahaSessionDriver
    private let human = HumanOmahaActionProvider()
    private let announcements = AnnouncementQueue()
    private let gate = HandGate()
    private let fastMode: Bool
    private let audio: AudioServicing
    private let audioDirector: OmahaAudioDirector
    private let conductor: SpeechConductor
    private let botChatter: OmahaBotChatter
    private let mode: AppVoiceOverMode
    private let rules: OmahaTableRules
    /// The hosting casino's audio palette (D-067): croupier voice + register, ambient,
    /// bot voices. Default `.skypool` (the Marble table's home).
    private let casinoAudio: CasinoAudio
    private let onLeave: (Int) -> Void

    private var leaveAfterHand = false
    /// Set once the player has stood up: stop narrating, never offer another turn (D-086).
    private var hasLeft = false
    /// Set when the HUMAN folds: the rest of the hand is fast-forwarded to the
    /// showdown instead of narrating rounds they cannot act in (D-087).
    private var fastForward = false
    private var eventQueue: [OmahaEventPayload] = []
    private var streamFinished = false
    private var turnContinuation: CheckedContinuation<Void, Never>?
    private var shownCategory: [Int: HandCategory] = [:]
    private var shownBestFive: [Int: [Card]] = [:]
    private var potAnnounced = false
    /// The turn info captured for the current raise box (its pot cap / shove state).
    private var raiseTurn: OmahaTurnInfo?

    /// - Parameter seed: `nil` (production default) → fresh RANDOM cards every hand
    ///   (D-047); a fixed value makes the whole session deterministic (tests/previews).
    public init(seed: UInt64? = nil, fastMode: Bool = false,
                audio: AudioServicing = NullAudioService(),
                mode: AppVoiceOverMode,
                rules: OmahaTableRules = .skypoolMarble,
                returnLabel: String,
                casinoAudio: CasinoAudio = .skypool,
                onLeave: @escaping (Int) -> Void = { _ in }) {
        self.fastMode = fastMode
        self.audio = audio
        self.mode = mode
        self.rules = rules
        self.returnLabel = returnLabel
        self.casinoAudio = casinoAudio
        self.onLeave = onLeave

        let rootSeed = seed ?? UInt64.random(in: .min ... .max)
        let startingChips = rules.buyIn
        let nameKeys = ["seat.name.sky.novice", "seat.name.sky.rock", "seat.name.sky.aggressor"]
        let bots = zip(1...3, rules.personalities).map { (id: $0.0, personality: $0.1) }
        var assignments = [OmahaSeatAssignment(position: 0, playerID: 0, chips: startingChips, provider: human)]
        assignments += bots.map { bot in
            OmahaSeatAssignment(position: bot.id, playerID: bot.id, chips: startingChips,
                                provider: OmahaBotActionProvider(HeuristicOmahaBot(personality: bot.personality,
                                                                                   seed: UInt64(bot.id) * 101 &+ rootSeed)))
        }
        self.driver = OmahaSessionDriver(capacity: 4, seats: assignments, buttonPosition: 0,
                                         smallBlind: rules.smallBlind, bigBlind: rules.bigBlind,
                                         seed: seed, escalation: rules.escalation)

        var names = [0: uiLocalized("seat.name.you")]
        for (bot, key) in zip(bots, nameKeys) { names[bot.id] = uiLocalized(key) }
        self.names = names

        let characters: [Int: BotCharacter] = [1: .novice, 2: .rock, 3: .aggressor]
        self.audioDirector = OmahaAudioDirector(audio: audio, heroSeatID: 0, characters: characters,
                                                seed: rootSeed, fastMode: fastMode,
                                                ambient: casinoAudio.ambient, voices: casinoAudio.botVoices)
        self.conductor = SpeechConductor(audio: audio, queue: announcements)
        self.botChatter = OmahaBotChatter(heroSeatID: 0, characters: characters, seed: rootSeed &+ 555,
                                          voices: casinoAudio.botVoices)

        self.state = OmahaTableState(
            seats: ([0] + bots.map { $0.id }).map { OmahaSeatPresentation(id: $0, position: $0, chips: startingChips) },
            heroSeatID: 0, smallBlind: rules.smallBlind, bigBlind: rules.bigBlind)
    }

    // MARK: - Leaving

    /// The player stands up IMMEDIATELY, mid-hand or not (D-086). Walking away is a
    /// decision, not a request: it costs whatever is already committed, and keeps only
    /// what is unambiguously the player's. The human provider is abandoned so the turn
    /// suspended right now — and every one still to come — resolves at once and the
    /// driver finishes at code speed.
    public func requestLeave() {
        guard !hasLeft else { return }
        hasLeft = true
        leaveAfterHand = true
        pendingLeave = false
        let remaining = state.seat(heroSeatID)?.chips ?? 0
        Task { await human.abandon() }
        onLeave(remaining)
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

    private func relay(_ stream: AsyncStream<OmahaSessionEvent>) async {
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
        while !Task.isCancelled, !hasLeft {
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

    private func present(_ payload: OmahaEventPayload) async {
        switch payload {
        case let .handBegan(_, _, _, _, _, _, _, seats):
            fastForward = false      // a new hand: narrate it fully again (D-087)
            conductor.handBegan()
            botChatter.handBegan(seats: seats)
            shownCategory.removeAll()
            shownBestFive.removeAll()
            potAnnounced = false
            state = OmahaTableReducer.reduce(state, payload)
            speak(payload, "hand-start")
            speakRole(payload)
            await pace(payload, human: OmahaPacing.seconds(for: payload))

        case .stakesEscalated:
            state = OmahaTableReducer.reduce(state, payload)
            speak(payload, "stakes-up")
            await pace(payload, human: 0.9)

        case let .streetOpened(street, cards):
            speak(payload, "street")
            let cardPace = mode.isEnabled ? 0.15 : 0.5
            for card in cards {
                state = OmahaTableReducer.reduce(state, .streetOpened(street: street, communityCards: [card]))
                await pause(cardPace)
            }
            await pace(payload, human: 0.25)

        case let .privateHoleCards(seatID, _) where seatID == heroSeatID:
            state = OmahaTableReducer.reduce(state, payload)
            speak(payload, "hero-cards")
            await pace(payload, human: 0.7)

        case let .playerActed(seatID, action):
            state.activeSeatID = seatID
            if seatID != heroSeatID { await pause(mode.isEnabled ? 0.1 : 0.55) }
            state = OmahaTableReducer.reduce(state, payload)
            speakAction(seatID: seatID, action: action)
            await pace(payload, human: 0.4)
            if state.activeSeatID == seatID { state.activeSeatID = nil }

        case let .handShown(seatID, _, category, bestFive):
            shownCategory[seatID] = category
            shownBestFive[seatID] = bestFive
            state = OmahaTableReducer.reduce(state, payload)
            speak(payload, "showdown")
            await pace(payload, human: 1.0)

        case .potAwarded:
            state = OmahaTableReducer.reduce(state, payload)
            speakPot(payload)
            await pace(payload, human: 1.1)

        case .handEnded:
            state = OmahaTableReducer.reduce(state, payload)
            await gate.release()
            await pace(payload, human: 1.2)

        case .sessionEnded:
            state = OmahaTableReducer.reduce(state, payload)
            finishSession()

        default:
            state = OmahaTableReducer.reduce(state, payload)
            speak(payload, "other")
            await pace(payload, human: OmahaPacing.seconds(for: payload))
        }
    }

    private func pace(_ payload: OmahaEventPayload, human: Double) async {
        // Fast-forwarding after the human folded: no pause until the payoff (D-087).
        if fastForward, !Self.isPayoff(payload) { return }
        announcements.pacedWhenSilent = mode.isEnabled
        if mode.isEnabled { await awaitSpokenChannelQuiet() } else { await pause(human) }
    }

    private func awaitSpokenChannelQuiet() async {
        SpokenLog.log("visual WAIT begin (omaha)")
        let quiet = await SpokenChannelPacing.awaitQuiet(
            isQuiet: { self.conductor.isIdle && self.announcements.isQuiet },
            isCancelled: { Task.isCancelled },
            maxWait: SpokenChannelPacing.adaptiveMaxWait(channelRemaining: self.conductor.channelRemaining),
            label: "omaha")
        SpokenLog.log("visual WAIT end (omaha) quiet=\(quiet)")
    }

    // MARK: - Speech

    /// The events carrying the RESULT — the only ones still narrated and paced while
    /// fast-forwarding past rounds the folded human cannot act in (D-087).
    static func isPayoff(_ payload: OmahaEventPayload) -> Bool {
        switch payload {
        case .handShown, .potAwarded, .handEnded, .playerBusted, .sessionEnded: return true
        default: return false
        }
    }

    private func speak(_ payload: OmahaEventPayload, _ reason: String = "") {
        if fastForward, !Self.isPayoff(payload) { return }
        say(OmahaSpeechMap.plan(for: payload, heroSeatID: heroSeatID, names: names), reason: reason)
    }

    private func speakRole(_ payload: OmahaEventPayload) {
        say(OmahaSpeechMap.roleAnnouncement(for: payload, heroSeatID: heroSeatID), reason: "role")
    }

    /// Sends a plan to the conductor, resolving the croupier LEAD + register fallback
    /// through the HOSTING CASINO's palette (D-067) — the Skypool's own croupier here.
    private func say(_ plan: OmahaSpeechPlan, reason: String) {
        let (lead, fbKey) = casinoAudio.croupier(plan.croupier)
        let fallback = fbKey.map(uiLocalized) ?? plan.croupierFallback.map(OmahaSpeechMap.text)
        conductor.say(lead: lead, synthesis: plan.synthesis.map(OmahaSpeechMap.text),
                      fallback: fallback, priority: priority(of: plan), reason: reason)
    }

    private func speakAction(seatID: Int, action: OmahaActedAction) {
        let plan = OmahaSpeechMap.plan(for: .playerActed(seatID: seatID, action: action),
                                       heroSeatID: heroSeatID, names: names)
        let synth = plan.synthesis.map(OmahaSpeechMap.text)
        if plan.croupier != nil {
            let (lead, fbKey) = casinoAudio.croupier(plan.croupier)
            conductor.say(lead: lead, leadCategory: .croupier, synthesis: synth,
                          fallback: fbKey.map(uiLocalized), priority: .medium, reason: "action-allin")
        } else if seatID != heroSeatID {
            // Skypool colour lead (AMBIENT: silent until produced, D-066), then the
            // informative attribution synthesis.
            let vob = botChatter.actionVoice(seat: seatID, action: action)
            conductor.say(lead: vob, leadCategory: .botVoice, synthesis: synth,
                          priority: .medium, reason: "opp-action")
        }
    }

    private func priority(of plan: OmahaSpeechPlan) -> AnnouncementPriority {
        if let s = plan.synthesis { return OmahaSpeechMap.priority(for: s) }
        if let f = plan.croupierFallback { return OmahaSpeechMap.priority(for: f) }
        return .medium
    }

    private func speakPot(_ payload: OmahaEventPayload) {
        guard case let .potAwarded(_, _, winners) = payload, !potAnnounced else { return }
        potAnnounced = true
        let plan = OmahaSpeechMap.plan(for: payload, heroSeatID: heroSeatID, names: names)
        let joined = winners.map { names[$0] ?? "\($0)" }.joined(separator: ", ")
        let ref = winners.first
        let line: OmahaSynthLine?
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
        let prio = line.map(OmahaSpeechMap.priority) ?? .high
        let (lead, fbKey) = casinoAudio.croupier(plan.croupier)
        conductor.say(lead: lead, synthesis: line.map(OmahaSpeechMap.text), fallback: fbKey.map(uiLocalized),
                      priority: prio, reason: "pot")
    }

    // MARK: - The human's betting turn

    private func runHumanTurn(_ context: OmahaBotContext) async {
        // The player has left: never offer a turn again (D-086).
        if hasLeft { return }
        let info = OmahaTurnInfo(from: context)
        humanTurn = info
        state.activeSeatID = heroSeatID
        conductor.flushPending()
        // The croupier's "it's your turn" — the casino's own voice (silent until its mp3
        // exists → the register fallback so the blind player always hears the turn, D-067).
        let (lead, fbKey) = casinoAudio.croupier(SoundCatalog.voSkyYourTurn)
        conductor.say(lead: lead, synthesis: nil,
                      fallback: fbKey.map(uiLocalized) ?? uiLocalized("omaha.announce.yourturn"),
                      priority: .high, reason: "your-turn")
        await withCheckedContinuation { turnContinuation = $0 }
        humanTurn = nil
        raiseBox = nil
        if state.activeSeatID == heroSeatID { state.activeSeatID = nil }
    }

    private func act(_ action: OmahaAction) {
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

    public func fold() {
        playUI(SoundCatalog.uiButtonTap)
        fastForward = true      // run straight to the showdown (D-087)
        act(.fold)
    }

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

    /// Whether the current raise box's max is a real all-in shove (else it's the pot).
    public var raiseCanShove: Bool { raiseTurn?.canShove ?? false }
    /// The Pot-Limit cap (max "to") for the current raise box, for the caption.
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

    /// Jump to the maximum: an all-in if the stack allows it, otherwise the pot cap.
    public func raiseMax() {
        guard var box = raiseBox else { return }
        playUI(SoundCatalog.uiAllInTrigger)
        box.toMax(); raiseBox = box
        announceRaiseValue(box)
    }

    /// Announce the new amount; at the pot-capped maximum say so explicitly (D-066).
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
        // Always a bet/raise "to" the chosen value: the engine makes it all-in
        // automatically when the value equals the whole stack; a pot-capped max is a
        // pot-sized bet, never a shove (Pot Limit — D-066).
        act(box.isBet ? .bet(box.value) : .raise(box.value))
    }

    public func cancelRaise() { playUI(SoundCatalog.uiBoxClose); raiseBox = nil }

    // MARK: - Outcome

    private func finishSession() {
        let heroChips = state.seat(heroSeatID)?.chips ?? 0
        if leaveAfterHand { onLeave(heroChips); return }
        let didWin = heroChips > 0
        outcome = didWin ? .won : .lost
        conductor.say(lead: nil, synthesis: OmahaSpeechMap.text(for: didWin ? .sessionWon : .sessionLost),
                      priority: .high, reason: "session-end")
    }

    public func returnToCasino() { onLeave(state.seat(heroSeatID)?.chips ?? 0) }

    // MARK: - Helpers

    private func playUI(_ id: SoundID) { audio.play(id, category: .ui) }

    private func pause(_ seconds: Double) async {
        let effective = fastMode ? 0.01 : seconds
        try? await Task.sleep(nanoseconds: UInt64(effective * 1_000_000_000))
    }
}
