// MachiavelliTableViewModel.swift
// =====================================================================
// Owns the Machiavelli match (human + one or two bots chosen by the progressive
// matchmaker, D-070), turns its code-speed event stream into a human-paced observable
// `MachiavelliTableState`, narrates it through the shared spoken channel, and drives the
// human's turn — a SEQUENCE of transformations (compose in the box / drag onto the
// table) closed by a terminal (Pass / Draw), D-072.
//
// The human's in-progress arrangement lives in a `MachiavelliWorkspace`. Both input
// modes mutate it and query the ENGINE PREDICATE (`MachiavelliRules`) for legality —
// no validity logic here (D-072). On a terminal the view model submits a
// `MachiavelliTurnPlan` to the `HumanMachiavelliTurnProvider`; the driver validates it
// against the turn-start snapshot and applies it. No game logic here.
//
// Reuses the shared infrastructure exactly: `SpeechConductor` + `AnnouncementQueue`,
// the app VoiceOver mode's adaptive pacing (D-034), `HandGate`, `GameOutcome`,
// `EndOverlay`. The audible wait (a bot thinking) is filled by the ambient director on
// the ambient channel, never by an announcement (D-072).

import Foundation
import GameWorld
import GameEngine
import Audio

/// One card in the composition box's scrollable chain: an instance index, its card, and
/// whether it is a hand card (upper part of the chain) or a table card (after the divider).
public struct MachiavelliChainCard: Equatable, Sendable, Identifiable {
    public let index: Int
    public let card: Card
    public let isHand: Bool
    public var id: Int { index }
}

/// The state of the modal composition box: the lower-half CHAIN (hand cards, a table
/// divider, then all laid cards) and the SELECTION (the pool, upper half). Selection is
/// kept in selection order so the pool reads in the order the player built it.
public struct MachiavelliBoxState: Equatable, Sendable {
    public var chain: [MachiavelliChainCard]
    public var selected: [Int]           // instance indices, in selection order

    public func isSelected(_ index: Int) -> Bool { selected.contains(index) }
    public var handCount: Int { chain.filter { $0.isHand }.count }
    public var selectedCards: [Card] {
        selected.compactMap { idx in chain.first { $0.index == idx }?.card }
    }
    public var poolEntries: [MachiavelliChainCard] {
        selected.compactMap { idx in chain.first { $0.index == idx } }
    }
}

@MainActor
public final class MachiavelliTableViewModel: ObservableObject {

    @Published public private(set) var state: MachiavelliTableState
    /// The human's in-progress arrangement, non-nil while it is their turn. (Internal:
    /// `MachiavelliWorkspace` is a UI implementation detail, consumed only by the view.)
    @Published private(set) var workspace: MachiavelliWorkspace?
    /// The composition box, non-nil while "Piazza" is open.
    @Published public private(set) var box: MachiavelliBoxState?
    @Published public private(set) var outcome: GameOutcome?
    @Published public private(set) var pendingLeave = false

    public let names: [Int: String]
    public let heroSeatID = 0
    public let returnLabel: String

    private let driver: MachiavelliSessionDriver
    private let human = HumanMachiavelliTurnProvider()
    private let announcements = AnnouncementQueue()
    private let gate = HandGate()
    private let fastMode: Bool
    private let audio: AudioServicing
    private let audioDirector: MachiavelliAudioDirector
    private let conductor: SpeechConductor
    private let mode: AppVoiceOverMode
    private let buyIn: Int
    private let onLeave: (Int) -> Void
    private let progress: MachiavelliProgressStore

    private var leaveAfterHand = false
    private var eventQueue: [MachiavelliEventPayload] = []
    private var streamFinished = false
    private var turnContinuation: CheckedContinuation<Void, Never>?
    /// The context the human's current turn started from (for "restart turn").
    private var turnContext: MachiavelliBotContext?

    /// - Parameter seed: `nil` (production) → fresh random cards every deal (D-047); a
    ///   fixed value makes the whole match deterministic (tests/previews).
    public init(seed: UInt64? = nil, fastMode: Bool = false,
                audio: AudioServicing = NullAudioService(),
                mode: AppVoiceOverMode,
                rules: MachiavelliTableRules = .clockTower,
                casinoAudio: CasinoAudio = .clockTower,
                progress: MachiavelliProgressStore = InMemoryMachiavelliProgress(),
                returnLabel: String,
                onLeave: @escaping (Int) -> Void = { _ in }) {
        self.fastMode = fastMode
        self.audio = audio
        self.mode = mode
        self.buyIn = rules.buyIn
        self.returnLabel = returnLabel
        self.onLeave = onLeave
        self.progress = progress

        let rootSeed = seed ?? UInt64.random(in: .min ... .max)
        // The progressive matchmaker picks ONE or TWO opponents by games played (D-070).
        let opponents = MachiavelliMatchmaker.opponents(gamesPlayed: progress.loadGamesPlayed(),
                                                        seed: rootSeed &* 2_654_435_761)
        var assignments = [MachiavelliSeatAssignment(position: 0, playerID: 0, provider: human)]
        var names = [0: uiLocalized("machiavelli.name.you")]
        var characters: [Int: MachiavelliCharacter] = [:]
        for (offset, personality) in opponents.enumerated() {
            let id = offset + 1
            assignments.append(MachiavelliSeatAssignment(
                position: id, playerID: id,
                provider: MachiavelliBotTurnProvider(
                    HeuristicMachiavelliBot(personality: personality, seed: UInt64(id) * 101 &+ rootSeed))))
            let character = Self.character(for: personality)
            characters[id] = character
            names[id] = uiLocalized(Self.nameKey(for: character))
        }
        self.names = names

        self.driver = MachiavelliSessionDriver(capacity: opponents.count + 1, seats: assignments,
                                               handSize: rules.handSize, victoryThreshold: rules.victoryThreshold,
                                               seed: seed)
        self.audioDirector = MachiavelliAudioDirector(audio: audio, heroSeatID: 0, characters: characters,
                                                      beds: casinoAudio.ambient, seed: rootSeed, fastMode: fastMode)
        self.conductor = SpeechConductor(audio: audio, queue: announcements)

        // A placeholder roster until `sessionBegan` rebuilds it (hero + the opponents).
        self.state = MachiavelliTableState(
            seats: ([0] + opponents.indices.map { $0 + 1 })
                .map { MachiavelliSeatPresentation(id: $0, position: $0) },
            heroSeatID: 0, phase: .idle, victoryThreshold: rules.victoryThreshold)
    }

    private static func character(for p: Personality) -> MachiavelliCharacter {
        switch p.name {
        case Personality.machiavelliProfessor.name: return .professor
        case Personality.machiavelliAdult.name:     return .adult
        default:                                    return .student
        }
    }
    private static func nameKey(for c: MachiavelliCharacter) -> String {
        switch c {
        case .student:   return "machiavelli.name.student"
        case .adult:     return "machiavelli.name.adult"
        case .professor: return "machiavelli.name.professor"
        }
    }

    // MARK: - Leaving

    public func requestLeave() {
        if outcome != nil { finishAndLeave(); return }
        leaveAfterHand = true
        pendingLeave = true
    }
    private func finishAndLeave() { onLeave(buyIn) }   // Machiavelli is prestige, not money → full refund (D-072)
    public func returnToCasino() { onLeave(buyIn) }

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

    private func relay(_ stream: AsyncStream<MachiavelliSessionEvent>) async {
        for await event in stream { eventQueue.append(event.payload) }
        streamFinished = true
    }

    private func produce() async {
        while !Task.isCancelled && driver.canDealNextHand {
            await gate.acquire()
            if Task.isCancelled || leaveAfterHand { break }
            _ = try? await driver.playHand()
            if leaveAfterHand { break }
        }
        await driver.endSession()
    }

    private func consume() async {
        while !Task.isCancelled {
            if !eventQueue.isEmpty {
                await present(eventQueue.removeFirst())
            } else if await human.isWaiting, let context = await human.pendingContext {
                await runHumanTurn(context)
            } else if streamFinished {
                break
            } else {
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        }
    }

    // MARK: - Presenting events (human paced)

    private func present(_ payload: MachiavelliEventPayload) async {
        switch payload {
        case .handBegan:
            conductor.handBegan()
            state = MachiavelliTableReducer.reduce(state, payload)
            let v = MachiavelliSpeechMap.voice(.handStart)
            let heroCount = state.seat(heroSeatID)?.handCount ?? 0
            // Specific content → synthesis carries it; the mp3 (when produced) is a
            // spoken flourish before it. No register fallback, so no D-051 double-speak.
            conductor.say(lead: v.sound, synthesis: MachiavelliSpeechMap.newHand(count: heroCount),
                          priority: .medium, reason: "hand-start")
            await pace(0.8)

        case let .tableChanged(seatID, table, placed, rearranged):
            let oldMelds = state.melds
            state = MachiavelliTableReducer.reduce(state, payload)
            if seatID != heroSeatID {
                speakOpponentMeld(seatID: seatID, oldMelds: oldMelds, newMelds: table,
                                  placed: placed, rearranged: rearranged)
            }
            await pace(0.6)

        case let .playerDrew(seatID, _):
            state = MachiavelliTableReducer.reduce(state, payload)
            if seatID != heroSeatID {
                let v = MachiavelliSpeechMap.voice(.drew)
                conductor.say(lead: v.sound, synthesis: MachiavelliSpeechMap.opponentDrew(name: name(seatID)),
                              priority: .medium, reason: "opp-drew")
            }
            await pace(0.5)

        case .handEnded:
            state = MachiavelliTableReducer.reduce(state, payload)
            speakHandEnd(payload)
            await gate.release()
            await pace(1.2)

        case let .matchEnded(winnerID, _, _):
            state = MachiavelliTableReducer.reduce(state, payload)
            let v = MachiavelliSpeechMap.voice(.matchEnd)
            conductor.say(lead: v.sound,
                          synthesis: MachiavelliSpeechMap.matchResult(heroWon: winnerID == heroSeatID,
                                                                      winnerName: name(winnerID)),
                          priority: .high, reason: "match-end")
            await pace(0.6)

        case .sessionEnded:
            state = MachiavelliTableReducer.reduce(state, payload)
            finishSession()

        case .botThinkingBegan, .botThinkingEnded, .turnBegan, .turnEnded, .privateHand, .privateDraw,
             .handDealt, .playerWentOut, .sessionBegan:
            // Reflected in state (thinking flag, hand, active seat); the ambient director
            // fills the audible wait. No spoken line here.
            state = MachiavelliTableReducer.reduce(state, payload)
            await pace(0.12)
        }
    }

    private func pace(_ human: Double) async {
        announcements.pacedWhenSilent = mode.isEnabled
        if mode.isEnabled { await awaitSpokenChannelQuiet() } else { await pause(human) }
    }

    private func awaitSpokenChannelQuiet() async {
        _ = await SpokenChannelPacing.awaitQuiet(
            isQuiet: { self.conductor.isIdle && self.announcements.isQuiet },
            isCancelled: { Task.isCancelled }, label: "machiavelli")
    }

    // MARK: - Speech helpers

    private func name(_ id: Int) -> String { names[id] ?? "\(id)" }

    /// Announces an opponent's laid combination(s): the new melds containing their placed
    /// cards, titled. Falls back to a plain count if none can be identified.
    private func speakOpponentMeld(seatID: Int, oldMelds: [[Card]], newMelds: [[Card]],
                                   placed: [Card], rearranged: Bool) {
        let placedSet = placed
        let titles: [String] = newMelds
            .filter { meld in meld.contains { card in placedSet.contains(card) } }
            .compactMap { MachiavelliSpeechMap.meldTitle($0) }
        let line = MachiavelliSpeechMap.opponentMelded(name: name(seatID), titles: titles,
                                                       placed: placed.count, rearranged: rearranged)
        let v = MachiavelliSpeechMap.voice(.meld)
        conductor.say(lead: v.sound, synthesis: line, priority: .medium, reason: "opp-meld")
    }

    private func speakHandEnd(_ payload: MachiavelliEventPayload) {
        guard case let .handEnded(_, _, handScores, _) = payload else { return }
        let entries = state.seats.sorted { $0.position < $1.position }
            .map { (name: name($0.id), points: handScores[$0.id] ?? 0) }
        let v = MachiavelliSpeechMap.voice(.handEnd)
        conductor.say(lead: v.sound, synthesis: MachiavelliSpeechMap.handScores(entries: entries),
                      priority: .high, reason: "hand-end")
    }

    // MARK: - The human's turn

    private func runHumanTurn(_ context: MachiavelliBotContext) async {
        turnContext = context
        workspace = MachiavelliWorkspace(hand: context.hand, table: context.table.map { $0.cards })
        state.activeSeatID = heroSeatID
        conductor.flushPending()
        let v = MachiavelliSpeechMap.voice(.yourTurn)
        conductor.say(lead: v.sound, fallback: uiLocalized(v.fallbackKey), priority: .high, reason: "your-turn")
        await withCheckedContinuation { turnContinuation = $0 }
        workspace = nil
        box = nil
        if state.activeSeatID == heroSeatID { state.activeSeatID = nil }
    }

    /// Restarts the current turn, discarding all in-progress placements (a safe undo).
    public func restartTurn() {
        guard let context = turnContext else { return }
        box = nil
        workspace = MachiavelliWorkspace(hand: context.hand, table: context.table.map { $0.cards })
        playUI(SoundCatalog.uiCancel)
        announcements.announceLiveValue(uiLocalized("machiavelli.turn.restarted"))
    }

    private func submit(_ terminal: MachiavelliTerminal) {
        guard let ws = workspace, let continuation = turnContinuation else { return }
        turnContinuation = nil
        let plan = MachiavelliTurnPlan(finalTable: ws.finalArrangement, terminal: terminal)
        workspace = nil
        box = nil
        Task {
            await human.submit(plan)
            continuation.resume()
        }
    }

    /// End the turn by passing (legal only when ≥1 card placed and the table is valid).
    public func passTurn() {
        guard workspace?.canPass == true else { return }
        playUI(SoundCatalog.uiConfirm)
        submit(.meld)
    }

    /// End the turn by drawing (legal only when nothing was placed on net).
    public func drawTurn() {
        guard workspace?.mustDraw == true else { return }
        playUI(SoundCatalog.uiButtonTap)
        submit(.draw)
    }

    // MARK: - The composition box (Piazza)

    /// Opens the composition box, built from the current workspace. Hypothetical: the
    /// table is untouched until a combination is confirmed (D-072).
    public func openBox() {
        guard let ws = workspace else { return }
        var chain: [MachiavelliChainCard] = ws.handCards.map {
            MachiavelliChainCard(index: $0.index, card: $0.card, isHand: true)
        }
        for group in ws.tableEntries {
            chain += group.map { MachiavelliChainCard(index: $0.index, card: $0.card, isHand: false) }
        }
        box = MachiavelliBoxState(chain: chain, selected: [])
        playUI(SoundCatalog.uiBoxOpen)
    }

    /// Toggles a card in/out of the pool. Announces the new SELECTION STATE — describing,
    /// never advising (D-072).
    public func toggleBoxCard(_ index: Int) {
        guard var b = box else { return }
        if let pos = b.selected.firstIndex(of: index) {
            b.selected.remove(at: pos)
            playUI(SoundCatalog.uiRaiseMinus)
        } else {
            b.selected.append(index)
            playUI(SoundCatalog.uiRaisePlus)
        }
        box = b
        announcements.announceLiveValue(MachiavelliSpeechMap.describeSelection(b.selectedCards))
    }

    /// Whether the box's Confirm should be enabled — asked of the ENGINE predicate.
    public var boxCanConfirm: Bool {
        guard let b = box, let ws = workspace else { return false }
        return ws.selectionIsLegalCombination(b.selected)
    }

    /// Confirms the composed combination: applies it to the workspace. The turn continues.
    public func confirmBox() {
        guard let b = box, var ws = workspace, ws.selectionIsLegalCombination(b.selected) else { return }
        ws.placeCombination(b.selected)
        workspace = ws
        box = nil
        playUI(SoundCatalog.uiConfirm)
        announcements.announceLiveValue(uiLocalized("machiavelli.box.confirmed",
                                                    MachiavelliSpeechMap.meldTitle(b.selectedCards) ?? ""))
    }

    /// Closes the box without applying (the pool is discarded, the table intact).
    public func closeBox() {
        box = nil
        playUI(SoundCatalog.uiBoxClose)
    }

    // MARK: - Drag (sighted) — same predicate, no box

    /// Drops a card instance onto an existing table combination (append) or, when
    /// `groupIndex` is nil, onto empty table space (a new combination). Mutates the same
    /// workspace the box does; the turn's terminal is gated on the SAME predicate.
    public func drop(cardIndex: Int, onGroup groupIndex: Int?) {
        guard var ws = workspace else { return }
        ws.moveToGroup(cardIndex, groupIndex: groupIndex)
        workspace = ws
        playUI(SoundCatalog.uiButtonTapSoft)
    }

    // MARK: - Outcome

    private func finishSession() {
        if leaveAfterHand { onLeave(buyIn); return }
        let heroScore = state.seat(heroSeatID)?.score ?? 0
        let topScore = state.seats.map { $0.score }.max() ?? 0
        let didWin = heroScore >= topScore && heroScore > 0
        progress.saveGamesPlayed(progress.loadGamesPlayed() + 1)   // one more encounter behind us (D-070)
        outcome = didWin ? .won : .lost
    }

    // MARK: - Helpers

    /// Announces a card on demand — used by a table-edge knob's custom actions to walk a
    /// combination's cards vertically (D-072). A live value so rapid walking collapses to
    /// the latest, and it routes through the queue (the single VoiceOver point, D-032).
    public func announce(_ text: String) { announcements.announceLiveValue(text) }

    private func playUI(_ id: SoundID) { audio.play(id, category: .ui) }

    private func pause(_ seconds: Double) async {
        let effective = fastMode ? 0.01 : seconds
        try? await Task.sleep(nanoseconds: UInt64(effective * 1_000_000_000))
    }
}
