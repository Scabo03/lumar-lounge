// BoardPriorityTests.swift
// =====================================================================
// D-108 — the community board must outrank opponent chatter (from the Phase-2 trace).
//
// On device the spoken channel saturates and drops the lowest tier. The flop that
// had just landed was LOW while opponent-action chatter was MEDIUM, so under
// pressure the player heard "giocatore 2 passa" but NOT the board — exactly the
// reported "it re-reads my hand instead of the community cards". The board is
// essential shared information (reachable otherwise only by manually focusing the
// board element); chatter is expendable. This pins the corrected ordering.

import XCTest
@testable import UI
@testable import GameEngine

final class BoardPriorityTests: XCTestCase {

    func testTexasBoardOutranksOpponentChatter() {
        let board = SpeechMap.priority(for: .communityCards([Card(.ace, .hearts),
                                                             Card(.six, .clubs),
                                                             Card(.ace, .diamonds)]))
        let chatter = SpeechMap.priority(for: .opponentAction(seat: 2, action: .folded))
        XCTAssertGreaterThan(board, chatter,
                             "the community board must not be dropped in favour of a fold announcement")
        XCTAssertEqual(chatter, .low, "opponent chatter is the lowest tier (D-108/D-094)")
        XCTAssertEqual(board, .medium, "the board is medium — below the player's own cards, above chatter")
    }

    func testOmahaBoardOutranksOpponentChatter() {
        let board = OmahaSpeechMap.priority(for: .communityCards([Card(.king, .spades),
                                                                  Card(.two, .hearts),
                                                                  Card(.seven, .clubs)]))
        let chatter = OmahaSpeechMap.priority(for: .opponentAction(seat: 1, action: .folded))
        XCTAssertGreaterThan(board, chatter, "Omaha board must outrank chatter too")
        XCTAssertEqual(chatter, .low)
        XCTAssertEqual(board, .medium)
    }
}
