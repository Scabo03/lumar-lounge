// StudAnnouncementLoadTests.swift
// =====================================================================
// THE MEASUREMENT (D-094).
//
// Stud is by a wide margin the most talkative table in the project, and the
// proposal on the table was to make it more so: name every opponent's new up
// card at every street. That is a real gap for a blind player — a sighted one
// watches the cards come down — but the spoken channel has a BUDGET (D-085),
// and past that budget it drops medium-priority lines. Adding announcements to
// a saturated channel does not add information; it trades information.
//
// So this measures before deciding, the way D-091 did for blackjack: lines and
// spoken SECONDS per hand, rendered from the shipped Italian file (the trap
// D-091 fell into once — without a bundle the renderer returns the key, so an
// unseamed measurement measures identifier lengths, D-093).

import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine

final class StudAnnouncementLoadTests: XCTestCase {

    private struct Load {
        var hands: Int
        var lines: Int
        var seconds: TimeInterval
        var upCardLines: Int
        /// spoken seconds per kind of line, so the load can be told apart.
        var byKind: [String: (lines: Int, seconds: TimeInterval)] = [:]
        var linesPerHand: Double { Double(lines) / Double(max(hands, 1)) }
        var secondsPerHand: TimeInterval { seconds / Double(max(hands, 1)) }
    }

    /// Renders the whole UI module through the shipped Italian strings.
    private func withItalian<T>(_ body: () throws -> T) rethrows -> T {
        UIStrings.override = BlackjackLocalizedStrings.italian
        defer { UIStrings.override = nil }
        return try body()
    }

    /// Plays real Stud hands at the ClockTower and totals what the player hears.
    @MainActor
    private func measure(hands: Int, seed: UInt64) async throws -> Load {
        let rules = StudTableRules.clockTower
        let seats = (0..<3).map { index in
            StudSeatAssignment(position: index, playerID: index, chips: 3000,
                               provider: StudBotActionProvider(
                                HeuristicStudBot(personality: rules.personalities[index % rules.personalities.count],
                                                 seed: UInt64(index) &+ seed)))
        }
        let driver = StudSessionDriver(capacity: 3, seats: seats,
                                       ante: rules.ante, bringIn: rules.bringIn, bet: rules.bet,
                                       seed: seed)

        var lines = 0, upCardLines = 0
        var seconds: TimeInterval = 0
        var byKind: [String: (lines: Int, seconds: TimeInterval)] = [:]
        let names = [0: "il Professore", 1: "lo Studente", 2: "il Bibliotecario"]
        let stream = await driver.events(as: EventViewer.player(0))
        let collector = Task { @MainActor in
            for await event in stream {
                let plan = StudSpeechMap.plan(for: event.payload, heroSeatID: 0, names: names)
                guard let line = plan.synthesis else { continue }
                lines += 1
                if case .upCard(_, _, let isHero) = line, !isHero { upCardLines += 1 }
                let cost = AnnouncementQueue.speakTime(StudSpeechMap.text(for: line))
                seconds += cost
                let kind = Self.kind(of: line)
                byKind[kind, default: (0, 0)].lines += 1
                byKind[kind, default: (0, 0)].seconds += cost
            }
        }
        let played = try await driver.run(maxHands: hands)
        await driver.endSession()
        _ = await collector.value

        return Load(hands: played.count, lines: lines, seconds: seconds,
                    upCardLines: upCardLines, byKind: byKind)
    }

    private static func kind(of line: StudSynthLine) -> String {
        switch line {
        case .heroCards:  return "hero cards"
        case let .upCard(_, _, isHero): return isHero ? "hero up card" : "opponent up card"
        case .bringIn:        return "bring-in"
        case .streetName:     return "street"
        case .opponentAction: return "opponent action"
        case .shown:          return "showdown hand"
        case .heroWon, .otherWon, .splitWon: return "pot"
        case .housePrize:     return "house prize"
        case .sessionWon, .sessionLost: return "session end"
        }
    }

    // MARK: - The current load, and what the enrichment would cost

    @MainActor
    func testStudSpokenLoadIsMeasuredAndTheEnrichmentIsPricedAgainstIt() async throws {
        let load = try await withItalian { Task { try await measure(hands: 40, seed: 4242) } }.value

        // The enrichment already EXISTS in the map: `upCardDealt` is planned for
        // every seat on every street, third through sixth. What it costs is
        // therefore measurable directly rather than hypothetically.
        let opponentUpPerHand = Double(load.upCardLines) / Double(max(load.hands, 1))

        print("""

        ── STUD SPOKEN LOAD, MEASURED ─────────────────────────
          hands                     \(load.hands)
          lines / hand              \(String(format: "%.2f", load.linesPerHand))
          spoken seconds / hand     \(String(format: "%.2f", load.secondsPerHand))
          of which opponent up cards\(String(format: "%.2f", opponentUpPerHand)) lines/hand
        ───────────────────────────────────────────────────────
        \(load.byKind.sorted { $0.value.seconds > $1.value.seconds }.map {
            String(format: "  %-20@ %5.2f lines/hand  %6.2f s/hand", $0.key,
                   Double($0.value.lines) / Double(max(load.hands, 1)),
                   $0.value.seconds / Double(max(load.hands, 1)))
        }.joined(separator: "\n"))
        ───────────────────────────────────────────────────────

        """)

        XCTAssertGreaterThan(load.hands, 15, "The measurement needs real hands behind it.")

        // The opponents' up cards ARE already announced at every street — this
        // pins that, so a future change cannot quietly drop the very information
        // the enrichment was proposed to add.
        XCTAssertGreaterThan(opponentUpPerHand, 1.0,
                             "Opponents' up cards must be narrated as they are dealt.")
    }

    // MARK: - Why no MORE is added: the channel is already the constraint

    @MainActor
    func testTheSpokenChannelIsAlreadySaturatedAtAStudShowdown() async throws {
        // A three-handed showdown is the worst moment: every surviving hand is
        // read, then the pot. This is where a per-street board recap would land,
        // and where the budget starts dropping medium lines.
        let italian = BlackjackLocalizedStrings.italian
        UIStrings.override = italian
        defer { UIStrings.override = nil }

        let showdown: [StudSynthLine] = [
            .shown(who: "il Professore", category: .flush,
                   bestFive: [Card(.ace, .hearts), Card(.jack, .hearts), Card(.nine, .hearts),
                              Card(.six, .hearts), Card(.three, .hearts)]),
            .shown(who: "lo Studente", category: .twoPair,
                   bestFive: [Card(.king, .spades), Card(.king, .clubs), Card(.seven, .hearts),
                              Card(.seven, .diamonds), Card(.queen, .spades)]),
            .heroWon(category: .flush, bestFive: nil),
        ]
        let showdownSeconds = showdown
            .map { AnnouncementQueue.speakTime(StudSpeechMap.text(for: $0)) }
            .reduce(0, +)

        print(String(format: "  showdown burst: %.2f s against a %.1f s channel budget",
                     showdownSeconds, SpeechConductor.channelBudget))

        // The finding that decides the question: the payoff burst ALONE already
        // exceeds the whole channel budget, so anything added at a street would
        // be competing with — and under D-085's rules, evicting — lines the
        // player needs more.
        XCTAssertGreaterThan(showdownSeconds, SpeechConductor.channelBudget,
                             "The showdown burst is expected to be at or over budget.")
    }

    // MARK: - What was done instead of adding lines (D-094)

    /// The enrichment was declined; the priority ORDER was corrected instead.
    /// Opponent chatter and opponents' up cards were both `.medium`, so a
    /// saturated channel evicted them alike — and the chatter is both more
    /// numerous and longer, so it was crowding out the one thing Stud is played
    /// on. Demoting the chatter costs nothing: no line added, no budget raised.
    func testUnderPressureTheChatterGivesWayBeforeTheUpCards() {
        let chatter = StudSpeechMap.priority(for: .opponentAction(who: "il Professore",
                                                                  action: .called(amount: 20, isAllIn: false)))
        let upCard = StudSpeechMap.priority(for: .upCard(who: "il Professore",
                                                         card: Card(.king, .hearts), isHero: false))
        let ownHand = StudSpeechMap.priority(for: .heroCards([Card(.ace, .spades)]))

        XCTAssertLessThan(chatter, upCard,
                          "An opponent's call must give way before the card in front of them.")
        XCTAssertLessThan(upCard, ownHand,
                          "And both give way before the player's own hand, which is never dropped.")
        XCTAssertEqual(ownHand, .high)
    }

    /// The budget itself is untouched — the fix was ordering, not headroom.
    func testTheChannelBudgetWasNotRaised() {
        XCTAssertEqual(SpeechConductor.channelBudget, 6.0,
                       "The budget was tuned on real device measurements (D-085); it stays.")
    }
}
