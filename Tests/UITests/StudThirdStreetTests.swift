// StudThirdStreetTests.swift
// =====================================================================
// D-094: on third street the hero holds THREE cards — two down and one up —
// and must hear them as one whole.
//
// D-089 removed the "seen by all" preamble so the hand would read
// continuously, but the split survived one event earlier: the pair of down
// cards was spoken on its own, under a label that says "your cards" while
// listing two of three, and the up card arrived as a separate sentence. What
// the player is told must match what the player holds.

import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine

final class StudThirdStreetTests: XCTestCase {

    private func italian<T>(_ body: () -> T) -> T {
        UIStrings.override = BlackjackLocalizedStrings.italian
        defer { UIStrings.override = nil }
        return body()
    }

    /// The rendered line names all three cards, in one sentence.
    func testTheHeroHearsAllThreeThirdStreetCardsAsOneLine() {
        let cards = [Card(.ace, .spades), Card(.four, .hearts), Card(.king, .clubs)]
        let text = italian { StudSpeechMap.text(for: .heroCards(cards)) }

        for expected in ["asso", "quattro", "re"] {
            XCTAssertTrue(text.lowercased().contains(expected),
                          "All three cards are named: missing '\(expected)' in “\(text)”")
        }

        // One sentence, not two: a single terminal stop, and no preamble
        // re-introducing the up/down split D-089 removed.
        XCTAssertEqual(text.filter { $0 == "." }.count, 1,
                       "The hand is one continuous line: “\(text)”")
        XCTAssertFalse(text.lowercased().contains("copert"),
                       "No down/up preamble in the hand line: “\(text)”")
        XCTAssertFalse(text.lowercased().contains("scopert"),
                       "No down/up preamble in the hand line: “\(text)”")
    }

    /// The seventh-street single down card still speaks on its own — there is
    /// nothing for it to join.
    func testTheSeventhStreetDownCardKeepsItsOwnLine() {
        let text = italian { StudSpeechMap.text(for: .heroCards([Card(.two, .diamonds)])) }
        XCTAssertTrue(text.lowercased().contains("due"), "The last card is named: “\(text)”")
        XCTAssertFalse(text.isEmpty)
    }

    /// The up/down distinction is not lost, only moved: it stays reachable on its
    /// own element (the same criterion D-083 applied to the opponents' boards).
    func testTheUpDownSplitStaysAvailableOnDemand() throws {
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("UI/StudTableView.swift"), encoding: .utf8)
        XCTAssertTrue(src.contains("\"hero.board\""),
                      "The player can still ask what the table sees of them.")
    }

    /// End to end on a real hand: the hero's third street produces exactly ONE
    /// spoken line, and it carries three cards.
    @MainActor
    func testARealThirdStreetProducesOneLineCarryingThreeCards() async throws {
        let rules = StudTableRules.clockTower
        let seats = (0..<3).map { index in
            StudSeatAssignment(position: index, playerID: index, chips: 3000,
                               provider: StudBotActionProvider(
                                HeuristicStudBot(personality: rules.personalities[index % rules.personalities.count],
                                                 seed: UInt64(index) &+ 77)))
        }
        let driver = StudSessionDriver(capacity: 3, seats: seats,
                                       ante: rules.ante, bringIn: rules.bringIn, bet: rules.bet,
                                       seed: 77)

        // The view model's coalescing rule, applied to the real event order.
        var pending: [Card]?
        var heroLines: [[Card]] = []
        let stream = await driver.events(as: EventViewer.player(0))
        let collector = Task { @MainActor in
            for await event in stream {
                switch event.payload {
                case let .privateDownCards(seat, cards) where seat == 0:
                    if cards.count == 2 { pending = cards } else { heroLines.append(cards) }
                case let .upCardDealt(seat, card, street) where seat == 0 && street == .third:
                    if let down = pending { heroLines.append(down + [card]); pending = nil }
                case .handBegan:
                    pending = nil
                default: break
                }
            }
        }
        _ = try await driver.run(maxHands: 1)
        await driver.endSession()
        _ = await collector.value

        let third = try XCTUnwrap(heroLines.first, "The hero is dealt a third street.")
        XCTAssertEqual(third.count, 3,
                       "Third street is spoken as one line of three cards, not two then one.")
        XCTAssertNil(pending, "Nothing is left held after the up card joins it.")
    }
}
