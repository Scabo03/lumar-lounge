// StudBoardReadoutTests.swift
// =====================================================================
// D-083 — the Stud opponent badge exposes the BOARD first, without preamble.

import XCTest
@testable import UI
import GameEngine

final class StudBoardReadoutTests: XCTestCase {

    /// A stand-in for the localization bundle: `.strings` files are not loaded under
    /// `swift test`, so tests inject a table of the real Italian formats.
    private let strings: [String: String] = [
        "stud.board.a11y": "%1$@, %2$@",
        "stud.board.none.a11y": "%@, nessuna scoperta",
        "stud.board.folded.a11y": "%@, ha fouldato",
        "stud.board.busted.a11y": "%@, eliminato",
        "seat.a11y.base": "%1$@, %2$d fiches",
        "seat.a11y.acting": "sta agendo",
        "seat.a11y.busted": "eliminato",
        "seat.a11y.folded": "ha fouldato",
        "seat.a11y.allIn": "ol-in",
        "stud.seat.bringin.a11y": "bring-in",
    ]

    private func loc(_ key: String, _ args: [CVarArg]) -> String {
        let format = strings[key] ?? key
        return args.isEmpty ? format : String(format: format, arguments: args)
    }

    private let upCards = [Card(.king, .hearts), Card(.ten, .spades)]

    private func board(name: String = "il Professore",
                       cards: [Card]? = nil,
                       folded: Bool = false, busted: Bool = false) -> String {
        StudBoardReadout.board(name: name, upCards: cards ?? upCards,
                               isFolded: folded, isBusted: busted, localized: loc)
    }

    // MARK: - The board is reachable without a preamble

    /// THE requirement (D-083): the element the player interrogates many times per hand
    /// says the OWNER and then the CARDS — no chips, no status, no "up cards:" label.
    func testBoardLeadsWithTheCardsAndCarriesNothingElse() {
        let line = board()
        XCTAssertTrue(line.hasPrefix("il Professore, "), "Unexpected board line: \(line)")
        XCTAssertFalse(line.contains("fiches"), "The board must not read chips: \(line)")
        XCTAssertFalse(line.lowercased().contains("scoperte"),
                       "The board must not carry an 'up cards:' preamble: \(line)")
        XCTAssertFalse(line.contains("sta agendo"), "The board must not read status: \(line)")
        // Everything after the name is cards and only cards.
        let afterName = line.replacingOccurrences(of: "il Professore, ", with: "")
        XCTAssertEqual(afterName, CardText.spoken(upCards))
    }

    /// The board line must be materially shorter than the OLD merged element it
    /// replaces (name + chips + status + "up cards:" + cards) — that saving, paid on
    /// every single interrogation, is the entire point of the split.
    func testBoardIsMuchShorterThanTheOldMergedElement() {
        let identity = StudBoardReadout.identity(name: "il Professore", chips: 3000,
                                                 isActive: true, isFolded: false, isBusted: false,
                                                 isAllIn: false, isBringIn: true, localized: loc)
        let oldMerged = identity + ", scoperte: " + CardText.spoken(upCards)
        XCTAssertLessThan(Double(board().count), Double(oldMerged.count) * 0.7,
                          "board '\(board())' vs old merged '\(oldMerged)'")
    }

    /// Name and chips did not vanish — they moved to their own element.
    func testIdentityStillCarriesNameChipsAndStatus() {
        let line = StudBoardReadout.identity(name: "il Professore", chips: 3000,
                                             isActive: true, isFolded: false, isBusted: false,
                                             isAllIn: false, isBringIn: false, localized: loc)
        XCTAssertTrue(line.contains("il Professore"))
        XCTAssertTrue(line.contains("3000"))
        XCTAssertTrue(line.contains("sta agendo"))
        // …and it does NOT repeat the cards.
        XCTAssertFalse(line.contains(CardText.spoken(upCards)))
    }

    // MARK: - States

    func testFoldedBustedAndEmptyBoardsAreStatedPlainly() {
        XCTAssertEqual(board(folded: true), "il Professore, ha fouldato")
        XCTAssertEqual(board(busted: true), "il Professore, eliminato")
        XCTAssertEqual(board(cards: []), "il Professore, nessuna scoperta")
    }

    // MARK: - Describes, never advises (CONVENTIONS §4)

    /// The board readout may state what lies on the table and nothing about what it
    /// could become — no "possible flush", no "dangerous", no "watch out".
    func testBoardDescribesAndNeverAdvises() {
        let advisory = ["possibil", "potrebbe", "attento", "attenzione", "pericol",
                        "minacc", "conviene", "dovresti", "meglio"]
        let flushy = [Card(.ace, .hearts), Card(.king, .hearts), Card(.queen, .hearts)]
        for line in [board(), board(cards: flushy), board(cards: []),
                     board(folded: true), board(busted: true)] {
            for word in advisory {
                XCTAssertFalse(line.lowercased().contains(word),
                               "Advisory language '\(word)' in board readout: \(line)")
            }
        }
    }

    /// The shipped Italian and English strings must exist and must not reintroduce a
    /// preamble before the cards.
    func testShippedStringsHaveNoPreamble() throws {
        for language in ["it", "en"] {
            let path = "Resources/\(language).lproj/Localizable.strings"
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
                throw XCTSkip("Strings file not reachable from the test working directory")
            }
            XCTAssertTrue(contents.contains("\"stud.board.a11y\""),
                          "\(language): missing stud.board.a11y")
            // The format must be exactly owner + cards, with no literal words between.
            let line = contents.split(separator: "\n")
                .first { $0.contains("\"stud.board.a11y\"") } ?? ""
            XCTAssertTrue(line.contains("%1$@, %2$@"),
                          "\(language) reintroduced a preamble in stud.board.a11y: \(line)")
        }
    }
}
