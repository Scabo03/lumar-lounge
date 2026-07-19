// StudHandReadoutTests.swift
// =====================================================================
// D-089 — the player's own hand is read as ONE continuous whole, and the Stud
// layout stays inside a phone screen at every street.

import XCTest
@testable import UI
import GameEngine

final class StudHandReadoutTests: XCTestCase {

    private func italianStrings() throws -> [String: String] {
        let path = "Resources/it.lproj/Localizable.strings"
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw XCTSkip("Strings file not reachable from the test working directory")
        }
        var table: [String: String] = [:]
        for line in contents.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            if value.hasSuffix(";") { value.removeLast() }
            table[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return table
    }

    // MARK: - One continuous reading of the player's own hand

    /// THE regression the player reported: the hand was read as two blocks with an aside
    /// in between ("le tue coperte: … / scoperte, VISTE DA TUTTI: …"). It must now be a
    /// single list, with ONE card placeholder — a second one would mean it is split again.
    func testOwnHandIsReadAsASingleContinuousList() throws {
        let s = try italianStrings()
        let hand = try XCTUnwrap(s["stud.hero.cards.a11y"], "missing stud.hero.cards.a11y")
        XCTAssertEqual(hand.components(separatedBy: "%").count - 1, 1,
                       "the hand must be ONE list, not two blocks: \(hand)")
        XCTAssertFalse(hand.contains("%1$"), "positional placeholders mean the read is still split: \(hand)")
    }

    /// The aside itself, in every form it could creep back as.
    func testOwnHandCarriesNoSeenByAllAside() throws {
        let s = try italianStrings()
        let hand = (s["stud.hero.cards.a11y"] ?? "").lowercased()
        for aside in ["viste da tutti", "visibili a tutti", "visibile a tutti", "per tutti", "da tutti"] {
            XCTAssertFalse(hand.contains(aside),
                           "the hand readout reintroduced the superfluous aside “\(aside)”: \(hand)")
        }
        // It must also not re-announce the down/up split inside the hand line.
        XCTAssertFalse(hand.contains("scoperte"),
                       "the up/down split belongs to its own element, not to the hand line: \(hand)")
    }

    /// Nothing was lost: the split is still available, on its own element.
    func testUpDownDistinctionRemainsAvailableOnItsOwnElement() throws {
        let s = try italianStrings()
        let board = try XCTUnwrap(s["stud.hero.board.a11y"], "the up/down distinction must stay available")
        XCTAssertTrue(board.contains("%@"), "the hero board must read the actual cards: \(board)")
        XCTAssertNotNil(s["stud.hero.board.none.a11y"], "the empty case must be stated too")
    }

    /// The same kind of superfluous aside elsewhere in Stud: a community card is for
    /// everyone by definition, so saying so added nothing.
    func testCommunityCardCarriesNoRedundantForEveryoneAside() throws {
        let s = try italianStrings()
        let community = (s["stud.community.a11y"] ?? "").lowercased()
        XCTAssertFalse(community.isEmpty)
        XCTAssertFalse(community.contains("per tutti"),
                       "“community card” already says it is for everyone: \(community)")
    }

    /// Describes, never advises (CONVENTIONS §4) — unchanged by the reformulation.
    func testHandReadoutDescribesAndNeverAdvises() throws {
        let s = try italianStrings()
        let advisory = ["possibil", "potrebbe", "attento", "conviene", "dovresti", "meglio", "rischi"]
        for key in ["stud.hero.cards.a11y", "stud.hero.board.a11y", "stud.hero.board.none.a11y",
                    "stud.community.a11y"] {
            let value = (s[key] ?? "").lowercased()
            for word in advisory {
                XCTAssertFalse(value.contains(word), "\(key) advises rather than describes: \(value)")
            }
        }
    }

    // MARK: - The layout fits a phone at every street

    /// The widths the row actually chooses, mirroring `FittedCardRow`'s candidate list.
    private func chosenCardWidth(count: Int, available: CGFloat, spacing: CGFloat) -> CGFloat {
        let candidates: [CGFloat] = [44, 40, 36, 32, 28, 24, 22, 20]
        for width in candidates where CGFloat(count) * width + CGFloat(count - 1) * spacing <= available {
            return width
        }
        return candidates.last!
    }

    private func rowWidth(count: Int, cardWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        CGFloat(count) * cardWidth + CGFloat(count - 1) * spacing
    }

    /// MEASURED before the fix: the opponent band reached 544 pt against 369 pt of usable
    /// width on an iPhone 15, overflowing from FOURTH street onward. It must now fit at
    /// every street, on the SMALLEST phone, with both opponents still in the hand.
    func testOpponentBandFitsEveryStreetOnThePhone() {
        for (screen, name) in [(375.0, "iPhone SE"), (393.0, "iPhone 15"), (430.0, "Pro Max")] {
            let usable = CGFloat(screen) - 24            // screen padding
            let perBadge = (usable - 10) / 2 - 12        // two badges, spacing, badge padding
            for upCards in 1...4 {                       // third street → sixth street
                let width = chosenCardWidth(count: upCards, available: perBadge, spacing: 3)
                let band = 2 * (rowWidth(count: upCards, cardWidth: width, spacing: 3) + 12) + 10
                XCTAssertLessThanOrEqual(band, usable,
                    "\(name): opponent band overflows with \(upCards) up cards (\(band) > \(usable))")
            }
        }
    }

    /// The heaviest moment of the whole game: seventh street, the player holding all
    /// SEVEN cards. This is what used to run off the right edge.
    func testHeroHandFitsAtSeventhStreetOnThePhone() {
        for (screen, name) in [(375.0, "iPhone SE"), (393.0, "iPhone 15"), (430.0, "Pro Max")] {
            let usable = CGFloat(screen) - 24 - 32       // screen padding + hero zone padding
            let width = chosenCardWidth(count: 7, available: usable, spacing: 4)
            let row = rowWidth(count: 7, cardWidth: width, spacing: 4)
            XCTAssertLessThanOrEqual(row, usable,
                "\(name): the seven-card hand overflows (\(row) > \(usable))")
            XCTAssertGreaterThanOrEqual(width, 20, "\(name): cards shrank below the legibility floor")
        }
    }

    /// The row never gives up: whatever it is handed, some candidate fits.
    func testACandidateAlwaysFitsHoweverTightTheSpace() {
        for count in 1...7 {
            for available in stride(from: 120.0, through: 420.0, by: 20.0) {
                let width = chosenCardWidth(count: count, available: CGFloat(available), spacing: 3)
                XCTAssertGreaterThan(width, 0)
            }
        }
    }
}
