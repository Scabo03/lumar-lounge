// StudBoardReadout.swift
// =====================================================================
// The two accessibility readouts of a Stud opponent badge, as PURE functions so
// they can be unit-tested without SwiftUI (D-017).
//
// D-083 — AN ACCESSIBLE ELEMENT LEADS WITH WHAT IS NEEDED MOST OFTEN.
// A Stud opponent badge used to be ONE element reading "name, chips, status, up
// cards: …". But reading opponents' boards is the strategic core of Stud and is
// done many times per hand, whereas name and chips are needed occasionally — so
// the blind player had to sit through the preamble every single time. The badge is
// now TWO sibling elements, with the board sorted FIRST:
//
//     opponent.N.board  →  "il Professore, re di cuori, dieci di picche"
//     opponent.N        →  "il Professore, 3000 fiches, sta agendo"
//
// The owner's name still leads the board line: with two opponents the read is
// useless without knowing whose board it is. That is IDENTITY, not preamble —
// what was removed is the chips, the status and the "up cards:" label.
//
// DESCRIBES, NEVER ADVISES (CONVENTIONS §4): the cards as they lie, never what
// they might mean.

import Foundation
import GameEngine

enum StudBoardReadout {

    /// The board line: the owner, then the cards, and nothing else.
    static func board(name: String, upCards: [Card],
                      isFolded: Bool, isBusted: Bool,
                      localized: (String, [CVarArg]) -> String = { uiLocalizedList($0, $1) }) -> String {
        if isBusted { return localized("stud.board.busted.a11y", [name]) }
        if isFolded { return localized("stud.board.folded.a11y", [name]) }
        guard !upCards.isEmpty else { return localized("stud.board.none.a11y", [name]) }
        return localized("stud.board.a11y", [name, CardText.spoken(upCards)])
    }

    /// The identity line: name, chips and status — everything the board line drops.
    static func identity(name: String, chips: Int, isActive: Bool,
                         isFolded: Bool, isBusted: Bool,
                         isAllIn: Bool, isBringIn: Bool,
                         localized: (String, [CVarArg]) -> String = { uiLocalizedList($0, $1) }) -> String {
        var parts = [localized("seat.a11y.base", [name, chips])]
        if isActive { parts.append(localized("seat.a11y.acting", [])) }
        if isBusted { parts.append(localized("seat.a11y.busted", [])) }
        else if isFolded { parts.append(localized("seat.a11y.folded", [])) }
        else {
            if isAllIn { parts.append(localized("seat.a11y.allIn", [])) }
            if isBringIn { parts.append(localized("stud.seat.bringin.a11y", [])) }
        }
        return parts.joined(separator: ", ")
    }
}
