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
    /// The end-of-game overlay's "return to <casino>" label — casino-specific (D-065).
    public let returnLabel: String

    private let driver: SessionDriver
    private let human = HumanActionProvider()
    /// The project-wide serial announcement channel (D-032). Shared with the
    /// conductor so croupier voices and synthesis act as one spoken channel.
    private let announcements = AnnouncementQueue()
    private let gate = HandGate()
    private let fastMode: Bool
    private let audio: AudioServicing
    private let audioDirector: AudioDirector
    /// The serial owner of the croupier voice + VoiceOver synthesis (D-029).
    private let conductor: SpeechConductor
    /// Decides the bots' occasional action voicelines, ordered before the synthesis.
    private let botChatter: BotChatter
    /// The app's own VoiceOver mode: when ON the visual timeline paces to the spoken
    /// channel; when OFF it keeps the fast internal rhythm (D-034).
    private let mode: AppVoiceOverMode
    /// This table's rules (blinds, personalities, boost — D-035/D-037).
    private let rules: TableRules
    /// The hosting casino's audio palette: croupier voice + register, ambient, bot
    /// voices (D-067). Default `.riverwood` = the identity palette → unchanged behaviour.
    private let casinoAudio: CasinoAudio
    /// Called when the player stands up: the remaining fiches to cash out (D-036).
    private let onLeave: (Int) -> Void
    /// The Fast table's decisive-hand boost (D-037).
    private let boost = DecisiveHandBoost()

    /// The player asked to stand up; they leave at the end of the current hand.
    @Published public private(set) var pendingLeave = false
    private var leaveAfterHand = false
    /// Whether any player folded pre-flop this hand (feeds the boost, D-037).
    private var preflopFoldThisHand = false
    private var sawFlopThisHand = false

    private var eventQueue: [EventPayload] = []
    private var streamFinished = false
    private var turnContinuation: CheckedContinuation<Void, Never>?
    /// Each seat's revealed hand at showdown (category + best five), for the pot
    /// conclusion line — spoken as a combination + kicker, never card-by-card (D-045).
    private var shownCategory: [Int: HandCategory] = [:]
    private var shownBestFive: [Int: [Card]] = [:]
    /// Guards the pot conclusion to once per hand — a hand can award several pots
    /// (main + side), and only the croupier mp3 was deduped before (D-029 fix).
    private var potAnnounced = false

    /// - Parameter seed: `nil` (production default) → the session deals fresh RANDOM
    ///   cards every hand (D-047); a fixed value makes the whole session deterministic
    ///   (used by tests/previews). The bots' and audio's own seeds derive from a
    ///   concrete root — random per session when `seed` is nil.
    public init(seed: UInt64? = nil, fastMode: Bool = false,
                audio: AudioServicing = NullAudioService(),
                mode: AppVoiceOverMode,
                rules: TableRules = .classic,
                returnLabel: String,
                casinoAudio: CasinoAudio = .riverwood,
                onLeave: @escaping (Int) -> Void = { _ in }) {
        self.fastMode = fastMode
        self.audio = audio
        self.mode = mode
        self.rules = rules
        self.returnLabel = returnLabel
        self.casinoAudio = casinoAudio
        self.onLeave = onLeave
        // A concrete root seed for the bots and audio: fixed in tests, random per
        // session in production. The DRIVER gets the optional `seed` directly, so a
        // nil seed makes it draw a fresh random seed for every hand.
        let rootSeed = seed ?? UInt64.random(in: .min ... .max)
        // Seat 0 is the human; seats 1–3 are the bots, taking this table's
        // personalities (Classic vs Fast, D-035/D-037). The buy-in is the stack.
        let startingChips = rules.buyIn
        let nameKeys = ["seat.name.novice", "seat.name.rock", "seat.name.aggressor"]
        let bots = zip(1...3, rules.personalities).map { (id: $0.0, personality: $0.1) }
        var assignments = [SeatAssignment(position: 0, playerID: 0, chips: startingChips, provider: human)]
        assignments += bots.map { bot in
            SeatAssignment(position: bot.id, playerID: bot.id, chips: startingChips,
                           provider: BotActionProvider(HeuristicBot(personality: bot.personality,
                                                                    seed: UInt64(bot.id) * 101 &+ rootSeed,
                                                                    equitySamples: fastMode ? 30 : 120)))
        }
        self.driver = SessionDriver(capacity: 4, seats: assignments, buttonPosition: 0,
                                    smallBlind: rules.smallBlind, bigBlind: rules.bigBlind, seed: seed)

        var names = [0: uiLocalized("seat.name.you")]
        for (bot, key) in zip(bots, nameKeys) { names[bot.id] = uiLocalized(key) }
        self.names = names

        // Each bot's CHARACTER (for voicelines) stays the same across tables; the
        // base big blind lets the director raise the ambient on a decisive hand.
        let characters: [Int: BotCharacter] = [1: .novice, 2: .rock, 3: .aggressor]
        self.audioDirector = AudioDirector(audio: audio, heroSeatID: 0, characters: characters,
                                           seed: rootSeed, fastMode: fastMode, baseBigBlind: rules.bigBlind,
                                           ambient: casinoAudio.ambient, voices: casinoAudio.botVoices)
        self.conductor = SpeechConductor(audio: audio, queue: announcements)
        self.botChatter = BotChatter(heroSeatID: 0, characters: characters, seed: rootSeed &+ 999,
                                     voices: casinoAudio.botVoices)

        self.state = TableState(
            seats: ([0] + bots.map { $0.id }).map { SeatPresentation(id: $0, position: $0, chips: startingChips) },
            phase: .idle, heroSeatID: 0
        )
    }

    // MARK: - Leaving the table (D-036)

    /// The player asks to stand up. Between hands (or after busting) they leave at
    /// once; during a hand it's deferred to the end of the current hand — nobody
    /// abandons a hand mid-way.
    public func requestLeave() {
        if outcome != nil { finishAndLeave(); return }   // already ended → leave now
        leaveAfterHand = true
        pendingLeave = true
    }

    private func finishAndLeave() {
        let remaining = state.seat(heroSeatID)?.chips ?? 0
        onLeave(remaining)
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
            if Task.isCancelled || leaveAfterHand { break }   // stood up between hands
            // Decisive hand (Fast table): double the blinds for this one hand via
            // the driver's additive override; the counter restarts afterwards (D-037).
            if rules.decisiveHandBoost && boost.isNextHandDecisive {
                _ = try? await driver.playHand(overrideSmallBlind: rules.smallBlind * 2,
                                               overrideBigBlind: rules.bigBlind * 2)
                boost.consumeDecisiveHand()
            } else {
                _ = try? await driver.playHand()
            }
            if leaveAfterHand { break }                        // stood up during the hand
            if (driver.chips(of: heroSeatID) ?? 0) == 0 { break } // hero busted
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
        case let .handBegan(_, _, _, _, _, _, bigBlind, seats):
            conductor.handBegan()          // reset once-per-hand voices (D-029)
            botChatter.handBegan(seats: seats)
            shownCategory.removeAll()
            shownBestFive.removeAll()
            potAnnounced = false
            preflopFoldThisHand = false
            sawFlopThisHand = false
            state = TableReducer.reduce(state, payload)
            speak(payload, "hand-start")   // croupier: "new hand"
            speakRole(payload)             // the human's OWN role, or silence (D-031)
            if bigBlind > rules.bigBlind { // decisive hand: blinds doubled (D-037)
                let (lead, fbKey) = casinoAudio.croupier(SoundCatalog.voHighStakes)
                conductor.say(lead: lead, fallback: fbKey.map(uiLocalized) ?? uiLocalized("announce.high.stakes"),
                              priority: .high, reason: "high-stakes")
            }
            await pace(payload, human: Pacing.seconds(for: payload))

        case let .streetOpened(.flop, cards):
            // The croupier says "flop", then the conductor reads the three cards
            // (D-029). Meanwhile reveal them one at a time.
            sawFlopThisHand = true
            speak(payload, "flop")
            let cardPace = mode.isEnabled ? 0.15 : 0.55
            for card in cards {
                state = TableReducer.reduce(state, .streetOpened(street: .flop, communityCards: [card]))
                await pause(cardPace)
            }
            await pace(payload, human: 0.25)

        case let .privateHoleCards(seatID, _) where seatID == heroSeatID:
            state = TableReducer.reduce(state, payload)
            speak(payload, "hero-cards")   // synthesis: the human's own cards
            await pace(payload, human: 0.6)

        case let .playerActed(seatID, action):
            state.activeSeatID = seatID
            if seatID != heroSeatID { await pause(mode.isEnabled ? 0.1 : 0.55) } // bot "thinking"
            state = TableReducer.reduce(state, payload)
            if case .folded = action, !sawFlopThisHand { preflopFoldThisHand = true } // for the boost (D-037)
            speakAction(seatID: seatID, action: action)   // opponent synthesis + vob_ (D-031)
            await pace(payload, human: 0.4)
            if state.activeSeatID == seatID { state.activeSeatID = nil }

        case let .handShown(seatID, _, category, bestFive):
            shownCategory[seatID] = category
            shownBestFive[seatID] = bestFive
            state = TableReducer.reduce(state, payload)
            speak(payload, "showdown")     // croupier "showdown" (once) + reveal
            await pace(payload, human: Pacing.seconds(for: payload))

        case .potAwarded:
            state = TableReducer.reduce(state, payload)
            speakPot(payload)              // pot voice once/hand + "you won with …"
            await pace(payload, human: 1.1)

        case .handEnded:
            state = TableReducer.reduce(state, payload)
            // Feed the boost BEFORE releasing the gate, so the producer sees the
            // updated streak when it acquires it for the next hand (D-037).
            if rules.decisiveHandBoost { boost.recordHand(anyFoldPreflop: preflopFoldThisHand) }
            await gate.release() // let the producer deal the next hand
            await pace(payload, human: 1.2)

        case .sessionEnded:
            state = TableReducer.reduce(state, payload)
            finishSession()

        default:
            // turn/river handled above; public hole-cards-dealt, busts, joins →
            // the map decides (mostly silent for the spoken layer).
            state = TableReducer.reduce(state, payload)
            speak(payload, "other")
            await pace(payload, human: Pacing.seconds(for: payload))
        }
    }

    /// Advances the visual timeline after an event. App VoiceOver mode ON → wait for
    /// the spoken channel (croupier + announcement queue) to go quiet, so eye and ear
    /// walk together (D-034); OFF → keep the fast internal human rhythm.
    private func pace(_ payload: EventPayload, human: Double) async {
        announcements.pacedWhenSilent = mode.isEnabled
        SpokenLog.log("visual \(eventLabel(payload)) mode=\(mode.isEnabled ? "ON" : "OFF")")
        if mode.isEnabled {
            await awaitSpokenChannelQuiet()
        } else {
            await pause(human)
        }
    }

    /// Blocks until the spoken channel is idle: the conductor has nothing left to
    /// play/hand off, and the announcement queue is not speaking or holding (D-034).
    /// Events that produced no announcement leave it idle, so they show at once.
    /// Bounded by a safeguard so a stuck voice can never freeze the UI (D-056).
    private func awaitSpokenChannelQuiet() async {
        SpokenLog.log("visual WAIT begin (texas)")
        let quiet = await SpokenChannelPacing.awaitQuiet(
            isQuiet: { self.conductor.isIdle && self.announcements.isQuiet },
            isCancelled: { Task.isCancelled },
            label: "texas")
        SpokenLog.log("visual WAIT end (texas) quiet=\(quiet)")
    }

    private func eventLabel(_ payload: EventPayload) -> String {
        switch payload {
        case .handBegan: return "handBegan"
        case .blindPosted: return "blindPosted"
        case .holeCardsDealt: return "holeCardsDealt"
        case .privateHoleCards: return "privateHoleCards"
        case .playerActed: return "playerActed"
        case .streetOpened: return "streetOpened"
        case .handShown: return "handShown"
        case .potAwarded: return "potAwarded"
        case .handEnded: return "handEnded"
        case .playerBusted: return "playerBusted"
        default: return "other"
        }
    }

    /// Sends an event's spoken plan (croupier lead and/or synthesis, with fallback)
    /// to the conductor.
    private func speak(_ payload: EventPayload, _ reason: String = "") {
        say(SpeechMap.plan(for: payload, heroSeatID: heroSeatID, names: names), reason: reason)
    }

    /// The human's OWN role at the start of the hand, or silence (D-031). The
    /// button mp3 isn't produced yet, so its declared synthesis fallback speaks.
    private func speakRole(_ payload: EventPayload) {
        say(SpeechMap.roleAnnouncement(for: payload, heroSeatID: heroSeatID), reason: "role")
    }

    /// Sends a plan to the conductor, resolving the croupier LEAD + register fallback
    /// through the HOSTING CASINO's palette (D-067). For the Riverwood palette this is
    /// the identity — same SoundID, and the plan's own fallback — so it is unchanged.
    private func say(_ plan: SpeechPlan, reason: String) {
        let (lead, fbKey) = casinoAudio.croupier(plan.croupier)
        let fallback = fbKey.map(uiLocalized) ?? plan.croupierFallback.map(SpeechMap.text)
        conductor.say(lead: lead, synthesis: plan.synthesis.map(SpeechMap.text),
                      fallback: fallback, priority: priority(of: plan), reason: reason)
    }

    /// An opponent's action: its attribution synthesis (medium priority — D-032),
    /// led by the croupier's "all-in" or an optional vob_ colour (D-031). The
    /// human's own action is silent (only physical sounds).
    private func speakAction(seatID: Int, action: ActedAction) {
        let plan = SpeechMap.plan(for: .playerActed(seatID: seatID, action: action),
                                  heroSeatID: heroSeatID, names: names)
        let synth = plan.synthesis.map(SpeechMap.text)
        if plan.croupier != nil {                       // all-in (own or opponent)
            let (lead, fbKey) = casinoAudio.croupier(plan.croupier)
            conductor.say(lead: lead, leadCategory: .croupier, synthesis: synth,
                          fallback: fbKey.map(uiLocalized), priority: .medium, reason: "action-allin")
        } else if seatID != heroSeatID {                // opponent ordinary action
            let vob = botChatter.actionVoice(seat: seatID, action: action)
            conductor.say(lead: vob, leadCategory: .botVoice, synthesis: synth,
                          priority: .medium, reason: "opp-action")
        }
    }

    /// The announcement priority carried by a plan's synthesis (or fallback).
    private func priority(of plan: SpeechPlan) -> AnnouncementPriority {
        if let s = plan.synthesis { return SpeechMap.priority(for: s) }
        if let f = plan.croupierFallback { return SpeechMap.priority(for: f) }
        return .medium
    }

    /// The pot conclusion, ONCE per hand (D-029 fix): the pot voice plus a
    /// synthesis naming the winner and — if it went to showdown — the winning hand.
    private func speakPot(_ payload: EventPayload) {
        guard case let .potAwarded(_, _, winners) = payload, !potAnnounced else { return }
        potAnnounced = true
        let plan = SpeechMap.plan(for: payload, heroSeatID: heroSeatID, names: names)
        let names = winners.map { self.names[$0] ?? "\($0)" }.joined(separator: ", ")
        let ref = winners.first    // any winner: in a split all share the same hand
        let line: SynthLine?
        if winners.count > 1 {
            line = .splitWon(who: names, category: ref.flatMap { shownCategory[$0] },
                             bestFive: ref.flatMap { shownBestFive[$0] })
        } else if winners.contains(heroSeatID) {
            line = .heroWon(category: shownCategory[heroSeatID], bestFive: shownBestFive[heroSeatID])
        } else if let winner = winners.first {
            line = .otherWon(who: self.names[winner] ?? "\(winner)",
                             category: shownCategory[winner], bestFive: shownBestFive[winner])
        } else {
            line = nil
        }
        let prio = line.map(SpeechMap.priority) ?? .high
        let (lead, fbKey) = casinoAudio.croupier(plan.croupier)
        conductor.say(lead: lead, synthesis: line.map(SpeechMap.text), fallback: fbKey.map(uiLocalized),
                      priority: prio, reason: "pot")
    }

    // MARK: - The human's turn

    private func runHumanTurn(_ context: BotContext) async {
        let info = HumanTurnInfo(from: context)
        humanTurn = info
        state.activeSeatID = heroSeatID
        // The croupier says "it's your turn" (vo_it_your_turn) — and that is ALL (D-055).
        // No "to call X, pot Y" synthesis: the Call button already shows "Call X" and
        // speaks the amount itself when VoiceOver reaches it, so the context line was
        // redundant and cut across the user reaching for their own cards.
        // The turn is time-critical: drop any stale narration still queued so the
        // "your turn" mp3 plays promptly rather than behind a backlog (D-031).
        conductor.flushPending()
        let (lead, fbKey) = casinoAudio.croupier(SoundCatalog.voYourTurn)
        conductor.say(lead: lead, synthesis: nil, fallback: fbKey.map(uiLocalized), priority: .high, reason: "your-turn")
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
        announcements.announceLiveValue(uiLocalized("announce.raise.value", box.value))
    }

    public func raiseMinus() {
        guard var box = raiseBox else { return }
        playUI(SoundCatalog.uiRaiseMinus)
        box.decrease(); raiseBox = box
        announcements.announceLiveValue(uiLocalized("announce.raise.value", box.value))
    }

    public func raiseAllIn() {
        guard var box = raiseBox else { return }
        playUI(SoundCatalog.uiAllInTrigger)
        box.toMax(); raiseBox = box
        announcements.announceLiveValue(uiLocalized("announce.raise.allin", box.value))
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
        // Voluntary stand-up: no win/lose overlay, just cash out and return (D-036).
        if leaveAfterHand {
            onLeave(heroChips)
            return
        }
        // Bust or session win: show the outcome, then the overlay's button returns
        // to the casino with the remaining fiches cashed out.
        let didWin = heroChips > 0
        outcome = didWin ? .won : .lost
        conductor.say(lead: nil, synthesis: SpeechMap.text(for: didWin ? .sessionWon : .sessionLost),
                      priority: .high, reason: "session-end")
    }

    /// Returns to the Riverwood, cashing out the remaining fiches (D-036). Called by
    /// the end-of-session overlay's button.
    public func returnToCasino() {
        onLeave(state.seat(heroSeatID)?.chips ?? 0)
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
