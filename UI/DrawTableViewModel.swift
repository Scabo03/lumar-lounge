// DrawTableViewModel.swift
// =====================================================================
// Owns the Five-Card Draw session (human + three bots), turns its code-speed event
// stream into a human-paced, observable `DrawTableState`, narrates it to VoiceOver,
// and drives the human's TWO decision points: a betting turn (fold/check/call/bet/
// raise — limit, fixed amounts) and a DRAW turn (a modal box to pick 0–4 cards to
// exchange). It forwards each to the `HumanDrawActionProvider`'s matching suspension.
//
// It reuses the Texas synchronisation shape (D-021): the stream is relayed into a
// MainActor queue; the betting bar / draw box appear when the paced display has
// caught up to the human's decision point (the provider is waiting). It reuses the
// shared spoken channel (`SpeechConductor` + `AnnouncementQueue`) and the app's
// VoiceOver mode for adaptive pacing (D-034). No game logic here.

import Foundation
import GameWorld
import GameEngine
import Audio

/// The information the action bar needs on the human's betting turn (limit).
public struct DrawBettingTurn: Equatable, Sendable {
    public let toCall: Int
    public let potSize: Int
    public let heroStack: Int
    public let currentBet: Int
    public let betUnit: Int
    public let callAmount: Int
    public let canFold: Bool
    public let canCheck: Bool
    public let canCall: Bool
    public let canBet: Bool
    public let canRaise: Bool
    public let hasOpeners: Bool

    init(from context: DrawBotContext) {
        let legal = context.legal
        toCall = context.toCall
        potSize = context.potSize
        heroStack = context.heroStack
        currentBet = context.currentBet
        betUnit = legal.betUnit
        callAmount = legal.callAmount
        canFold = legal.canFold
        canCheck = legal.canCheck
        canCall = legal.canCall
        canBet = legal.canBet
        canRaise = legal.canRaise
        hasOpeners = legal.hasOpeners
    }

    /// The total street bet an open makes (limit: one bet unit).
    public var betTo: Int { betUnit }
    /// The total street bet a raise makes (limit: current + one bet unit).
    public var raiseTo: Int { currentBet + betUnit }
}

/// The state of the modal draw box: the five cards and which are marked to discard.
public struct DrawBoxState: Equatable, Sendable {
    public let cards: [Card]
    public var selected: Set<Card>

    public init(cards: [Card], selected: Set<Card> = []) {
        self.cards = cards
        self.selected = selected
    }

    public func isSelected(_ card: Card) -> Bool { selected.contains(card) }
    public var discardCount: Int { selected.count }
    /// The discards in the on-screen (left-to-right) order of the five cards.
    public var orderedDiscards: [Card] { cards.filter { selected.contains($0) } }
}

@MainActor
public final class DrawTableViewModel: ObservableObject {

    @Published public private(set) var state: DrawTableState
    /// Non-nil while it's the human's betting turn.
    @Published public private(set) var bettingTurn: DrawBettingTurn?
    /// Non-nil while the human's draw box is open.
    @Published public private(set) var drawBox: DrawBoxState?
    /// Set once the session ends (win/lose overlay).
    @Published public private(set) var outcome: GameOutcome?
    @Published public private(set) var pendingLeave = false

    public let names: [Int: String]
    public let heroSeatID = 0

    private let driver: DrawSessionDriver
    private let human = HumanDrawActionProvider()
    private let announcements = AnnouncementQueue()
    private let gate = HandGate()
    private let fastMode: Bool
    private let audio: AudioServicing
    private let audioDirector: DrawAudioDirector
    private let conductor: SpeechConductor
    private let botChatter: DrawBotChatter
    private let mode: AppVoiceOverMode
    private let rules: DrawTableRules
    private let onLeave: (Int) -> Void

    private var leaveAfterHand = false

    private var eventQueue: [DrawEventPayload] = []
    private var streamFinished = false
    private var turnContinuation: CheckedContinuation<Void, Never>?
    private var drawContinuation: CheckedContinuation<Void, Never>?
    private var shownCategory: [Int: HandCategory] = [:]
    private var shownBestFive: [Int: [Card]] = [:]
    private var potAnnounced = false

    /// - Parameter seed: `nil` (production default) → the session deals fresh RANDOM
    ///   cards every deal (D-047); a fixed value makes the whole session deterministic
    ///   (tests/previews). The bots' and audio's seeds derive from a concrete root —
    ///   random per session when `seed` is nil.
    public init(seed: UInt64? = nil, fastMode: Bool = false,
                audio: AudioServicing = NullAudioService(),
                mode: AppVoiceOverMode,
                rules: DrawTableRules = .riverwoodWhiskey,
                onLeave: @escaping (Int) -> Void = { _ in }) {
        self.fastMode = fastMode
        self.audio = audio
        self.mode = mode
        self.rules = rules
        self.onLeave = onLeave

        // Concrete root seed for bots/audio (random per session in production); the
        // DRIVER gets the optional `seed`, so nil makes it draw a fresh random seed
        // for every deal.
        let rootSeed = seed ?? UInt64.random(in: .min ... .max)
        let startingChips = rules.buyIn
        let nameKeys = ["seat.name.novice", "seat.name.rock", "seat.name.aggressor"]
        let bots = zip(1...3, rules.personalities).map { (id: $0.0, personality: $0.1) }
        var assignments = [DrawSeatAssignment(position: 0, playerID: 0, chips: startingChips, provider: human)]
        assignments += bots.map { bot in
            DrawSeatAssignment(position: bot.id, playerID: bot.id, chips: startingChips,
                               provider: DrawBotActionProvider(HeuristicDrawBot(personality: bot.personality,
                                                                                seed: UInt64(bot.id) * 101 &+ rootSeed)))
        }
        self.driver = DrawSessionDriver(capacity: 4, seats: assignments, buttonPosition: 0,
                                        ante: rules.ante, smallBet: rules.smallBet, bigBet: rules.bigBet, seed: seed)

        var names = [0: uiLocalized("seat.name.you")]
        for (bot, key) in zip(bots, nameKeys) { names[bot.id] = uiLocalized(key) }
        self.names = names

        let characters: [Int: BotCharacter] = [1: .novice, 2: .rock, 3: .aggressor]
        self.audioDirector = DrawAudioDirector(audio: audio, heroSeatID: 0, characters: characters,
                                               seed: rootSeed, fastMode: fastMode)
        self.conductor = SpeechConductor(audio: audio, queue: announcements)
        self.botChatter = DrawBotChatter(heroSeatID: 0, characters: characters, seed: rootSeed &+ 777)

        self.state = DrawTableState(
            seats: ([0] + bots.map { $0.id }).map { DrawSeatPresentation(id: $0, position: $0, chips: startingChips) },
            phase: .idle, heroSeatID: 0)
    }

    // MARK: - Leaving

    public func requestLeave() {
        if outcome != nil { finishAndLeave(); return }
        leaveAfterHand = true
        pendingLeave = true
    }

    private func finishAndLeave() {
        onLeave(state.seat(heroSeatID)?.chips ?? 0)
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

    private func relay(_ stream: AsyncStream<DrawSessionEvent>) async {
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
            } else if await human.pendingAction != nil {
                await runBettingTurn(await human.pendingAction!)
            } else if await human.pendingDraw != nil {
                await runDrawTurn(await human.pendingDraw!)
            } else if streamFinished {
                break
            } else {
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        }
    }

    // MARK: - Presenting events (human paced)

    private func present(_ payload: DrawEventPayload) async {
        switch payload {
        case let .handBegan(_, _, _, _, _, _, carriedPot, seats):
            conductor.handBegan()
            botChatter.handBegan(seats: seats)
            shownCategory.removeAll()
            shownBestFive.removeAll()
            potAnnounced = false
            state = DrawTableReducer.reduce(state, payload)
            speak(payload, "ante")
            if carriedPot > 0 {                       // the progressive pot grew (D-040)
                conductor.say(lead: SoundCatalog.voCarriedPot,
                              synthesis: DrawSpeechMap.text(for: .carriedPot(carriedPot)),
                              fallback: DrawSpeechMap.text(for: .carriedPot(carriedPot)),
                              priority: .high, reason: "carried-pot")
            }
            await pace(payload, human: DrawPacing.seconds(for: payload))

        case let .privateCards(seatID, _) where seatID == heroSeatID:
            state = DrawTableReducer.reduce(state, payload)
            speak(payload, "hero-cards")
            await pace(payload, human: 0.6)

        case let .playerActed(seatID, action, _):
            state.activeSeatID = seatID
            if seatID != heroSeatID { await pause(mode.isEnabled ? 0.1 : 0.5) }
            state = DrawTableReducer.reduce(state, payload)
            speakAction(seatID: seatID, action: action)
            await pace(payload, human: 0.4)
            if state.activeSeatID == seatID { state.activeSeatID = nil }

        case .passedIn:
            state = DrawTableReducer.reduce(state, payload)
            speak(payload, "passed-in")
            await pace(payload, human: 1.2)

        case .drawPhaseBegan:
            state = DrawTableReducer.reduce(state, payload)
            speak(payload, "draw-phase")
            await pace(payload, human: 0.6)

        case let .playerDrew(seatID, _):
            state.activeSeatID = seatID
            if seatID != heroSeatID { await pause(mode.isEnabled ? 0.1 : 0.5) }
            state = DrawTableReducer.reduce(state, payload)
            speak(payload, "drew")
            await pace(payload, human: 0.5)
            if state.activeSeatID == seatID { state.activeSeatID = nil }

        case let .privateDrawnCards(seatID, _) where seatID == heroSeatID:
            state = DrawTableReducer.reduce(state, payload)
            speak(payload, "hero-drew")
            await pace(payload, human: 0.6)

        case let .handShown(seatID, _, category, bestFive):
            shownCategory[seatID] = category
            shownBestFive[seatID] = bestFive
            state = DrawTableReducer.reduce(state, payload)
            speak(payload, "showdown")
            await pace(payload, human: 1.0)

        case .openersDisqualified:
            state = DrawTableReducer.reduce(state, payload)
            speak(payload, "disqualified")
            await pace(payload, human: 1.2)

        case .potAwarded:
            state = DrawTableReducer.reduce(state, payload)
            speakPot(payload)
            await pace(payload, human: 1.1)

        case .handEnded:
            state = DrawTableReducer.reduce(state, payload)
            await gate.release()
            await pace(payload, human: 1.2)

        case .sessionEnded:
            state = DrawTableReducer.reduce(state, payload)
            finishSession()

        default:
            state = DrawTableReducer.reduce(state, payload)
            speak(payload, "other")
            await pace(payload, human: DrawPacing.seconds(for: payload))
        }
    }

    private func pace(_ payload: DrawEventPayload, human: Double) async {
        announcements.pacedWhenSilent = mode.isEnabled
        if mode.isEnabled { await awaitSpokenChannelQuiet() } else { await pause(human) }
    }

    private func awaitSpokenChannelQuiet() async {
        while !(conductor.isIdle && announcements.isQuiet) {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    // MARK: - Speech

    private func speak(_ payload: DrawEventPayload, _ reason: String = "") {
        let plan = DrawSpeechMap.plan(for: payload, heroSeatID: heroSeatID, names: names)
        conductor.say(lead: plan.croupier, synthesis: plan.synthesis.map(DrawSpeechMap.text),
                      fallback: plan.croupierFallback.map(DrawSpeechMap.text),
                      priority: priority(of: plan), reason: reason)
    }

    private func speakAction(seatID: Int, action: DrawActedAction) {
        let plan = DrawSpeechMap.plan(for: .playerActed(seatID: seatID, action: action, round: .first),
                                      heroSeatID: heroSeatID, names: names)
        let synth = plan.synthesis.map(DrawSpeechMap.text)
        if plan.croupier != nil {
            conductor.say(lead: plan.croupier, leadCategory: .croupier, synthesis: synth,
                          priority: .medium, reason: "action-allin")
        } else if seatID != heroSeatID {
            let vob = botChatter.actionVoice(seat: seatID, action: action)
            conductor.say(lead: vob, leadCategory: .botVoice, synthesis: synth,
                          priority: .medium, reason: "opp-action")
        }
    }

    private func priority(of plan: DrawSpeechPlan) -> AnnouncementPriority {
        if let s = plan.synthesis { return DrawSpeechMap.priority(for: s) }
        if let f = plan.croupierFallback { return DrawSpeechMap.priority(for: f) }
        return .medium
    }

    private func speakPot(_ payload: DrawEventPayload) {
        guard case let .potAwarded(_, _, winners) = payload, !potAnnounced else { return }
        potAnnounced = true
        let plan = DrawSpeechMap.plan(for: payload, heroSeatID: heroSeatID, names: names)
        let joined = winners.map { names[$0] ?? "\($0)" }.joined(separator: ", ")
        let ref = winners.first    // any winner: in a split all share the same hand
        let line: DrawSynthLine?
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
        let prio = line.map(DrawSpeechMap.priority) ?? .high
        conductor.say(lead: plan.croupier, synthesis: line.map(DrawSpeechMap.text), priority: prio, reason: "pot")
    }

    // MARK: - The human's betting turn

    private func runBettingTurn(_ context: DrawBotContext) async {
        let info = DrawBettingTurn(from: context)
        bettingTurn = info
        state.activeSeatID = heroSeatID
        let callContext: String? = info.toCall > 0
            ? DrawSpeechMap.text(for: .yourTurnContext(toCall: info.toCall, pot: info.potSize)) : nil
        conductor.flushPending()
        conductor.say(lead: SoundCatalog.voYourTurn, synthesis: callContext, priority: .high, reason: "your-turn")
        await withCheckedContinuation { turnContinuation = $0 }
        bettingTurn = nil
        if state.activeSeatID == heroSeatID { state.activeSeatID = nil }
    }

    private func act(_ action: DrawAction) {
        guard let continuation = turnContinuation else { return }
        turnContinuation = nil
        bettingTurn = nil
        Task {
            await human.submitAction(action)
            continuation.resume()
        }
    }

    public func fold() { playUI(SoundCatalog.uiButtonTap); act(.fold) }
    public func checkOrCall() {
        guard let turn = bettingTurn else { return }
        playUI(SoundCatalog.uiButtonTap)
        act(turn.canCheck ? .check : .call)
    }
    public func betOpen() {
        guard bettingTurn?.canBet == true else { return }
        playUI(SoundCatalog.uiConfirm)
        act(.bet)
    }
    public func raise() {
        guard bettingTurn?.canRaise == true else { return }
        playUI(SoundCatalog.uiConfirm)
        act(.raise)
    }

    // MARK: - The human's draw turn

    private func runDrawTurn(_ context: DrawDrawContext) async {
        drawBox = DrawBoxState(cards: context.cards)
        state.activeSeatID = heroSeatID
        conductor.flushPending()
        // The box's own focus reads the title + count; no separate croupier line.
        await withCheckedContinuation { drawContinuation = $0 }
        drawBox = nil
        if state.activeSeatID == heroSeatID { state.activeSeatID = nil }
    }

    /// Toggles a card's selection in the draw box (max four). Announces the new
    /// state; a rejected fifth selection is announced too (D-044).
    public func toggleDrawCard(_ card: Card) {
        guard var box = drawBox else { return }
        if box.selected.contains(card) {
            box.selected.remove(card)
            playUI(SoundCatalog.uiRaiseMinus)
            announcements.announceLiveValue(uiLocalized("draw.box.deselected", CardText.spoken(card)))
        } else if box.selected.count < 4 {
            box.selected.insert(card)
            playUI(SoundCatalog.uiRaisePlus)
            announcements.announceLiveValue(uiLocalized("draw.box.selected", CardText.spoken(card)))
        } else {
            playUI(SoundCatalog.uiCancel)
            announcements.announceLiveValue(uiLocalized("draw.box.max"))
            return
        }
        drawBox = box
    }

    public func confirmDraw() {
        guard let box = drawBox, let continuation = drawContinuation else { return }
        drawContinuation = nil
        let discards = box.orderedDiscards
        drawBox = nil
        playUI(SoundCatalog.uiConfirm)
        Task {
            await human.submitDiscards(discards)
            continuation.resume()
        }
    }

    // MARK: - Outcome

    private func finishSession() {
        let heroChips = state.seat(heroSeatID)?.chips ?? 0
        if leaveAfterHand { onLeave(heroChips); return }
        let didWin = heroChips > 0
        outcome = didWin ? .won : .lost
        conductor.say(lead: nil, synthesis: DrawSpeechMap.text(for: didWin ? .sessionWon : .sessionLost),
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
