// MachiavelliSpeechMap.swift
// =====================================================================
// The pure, testable authority for what the Machiavelli table SAYS (D-072): the title
// of a laid combination ("scala di picche dal cinque al dieci", "tris di assi"), the
// read-out of the composition box's SELECTION STATE, and the ClockTower speaker's lines
// for opponent moves and end-of-hand scores. No SwiftUI — just localized strings.
//
// A HARD BOUNDARY, written as a permanent principle (CONVENTIONS §4, D-072): the system
// DESCRIBES the state, it never ADVISES the move. Saying "four cards selected, an
// incomplete heart run" is description — exactly what the sighted player sees in the
// pool. Saying "you need the seven to complete it" is advice — playing the game for the
// player, which never happens to the sighted. When the selection becomes a LEGAL
// combination the fact is stated plainly ("heart run five to nine, valid"), because that
// is the same information the sighted player gets from the Confirm button unlocking.
//
// The ClockTower "speaker" (NOT a croupier — Machiavelli has no pot/showdown) uses the
// `vo_it_clock_*` slots; each is INFORMATIVE and falls back to synthesis (D-030) until
// the mp3 is produced. Register: erudite, measured, learned; character UNDECIDED (D-072).

import Foundation
import GameEngine
import Audio

enum MachiavelliSpeechMap {

    // MARK: - Combination titles

    /// The spoken title of a laid combination, e.g. "tris di assi", "poker di re",
    /// "scala di picche dal cinque al dieci". `nil` if the cards are not a legal meld.
    static func meldTitle(_ cards: [Card]) -> String? {
        guard let meld = Meld(cards) else { return nil }
        switch meld.form {
        case .group:
            let key = meld.size >= 4 ? "machiavelli.meld.poker" : "machiavelli.meld.tris"
            return uiLocalized(key, plural(meld.cards[0].rank))
        case .run:
            let low = meld.cards.first!.rank
            let high = meld.cards.last!.rank
            let suit = uiLocalized("card.suit.\(CardText.suitKey(meld.cards[0].suit))")
            return uiLocalized("machiavelli.meld.run", suit, dalRank(low), alRank(high))
        }
    }

    // MARK: - Selection-state read-out (DESCRIBE, never ADVISE — D-072)

    /// The state of the box selection: how many cards, and WHAT the selection currently
    /// is. Describes only — never names the card that would complete it (that would be
    /// advice). When the selection is a legal combination, states it as a fact ("valid").
    static func describeSelection(_ cards: [Card]) -> String {
        guard !cards.isEmpty else { return uiLocalized("machiavelli.sel.none") }
        if let title = meldTitle(cards) {
            return uiLocalized("machiavelli.sel.valid", cards.count, title)
        }
        let ranks = Set(cards.map { $0.rank })
        let suits = Set(cards.map { $0.suit })
        if ranks.count == 1 {
            return uiLocalized("machiavelli.sel.samerank", cards.count, plural(cards[0].rank))
        }
        if suits.count == 1 {
            // Same suit, distinct ranks → a partial run in the making. Stating "incomplete
            // run" is description (the sighted sees a row of one suit not yet consecutive),
            // NOT advice — it never says which card is missing.
            let suit = uiLocalized("card.suit.\(CardText.suitKey(cards[0].suit))")
            return ranks.count == cards.count
                ? uiLocalized("machiavelli.sel.samesuit.run", cards.count, suit)
                : uiLocalized("machiavelli.sel.samesuit", cards.count, suit)
        }
        return uiLocalized("machiavelli.sel.loose", cards.count)
    }

    // MARK: - Table overview (a knob's title) + broken-combination declaration (D-073)

    /// The overview title spoken by a table-edge knob: the combination above it, or —
    /// when that combination is BROKEN — a declaration that it is incomplete (D-073).
    static func knobTitle(_ cards: [Card]) -> String {
        meldTitle(cards) ?? brokenTitle(cards)
    }

    /// DECLARES a broken combination — describing WHAT it is and that it does not stand,
    /// never HOW to repair it (D-073). This is the same information the sighted player
    /// gets from seeing the table decomposed; it is description, not advice: it names the
    /// broken combination ("scala di picche incompleta", "combinazione incompleta di
    /// sette") and never says which card is missing or where to take it.
    static func brokenTitle(_ cards: [Card]) -> String {
        let ranks = Set(cards.map { $0.rank })
        let suits = Set(cards.map { $0.suit })
        if ranks.count == 1 {
            return uiLocalized("machiavelli.broken.samerank", cards.count, plural(cards[0].rank))
        }
        if suits.count == 1 {
            let suit = uiLocalized("card.suit.\(CardText.suitKey(cards[0].suit))")
            return uiLocalized("machiavelli.broken.samesuit", suit)
        }
        return uiLocalized("machiavelli.broken.generic", cards.count)
    }

    // MARK: - The ClockTower speaker (event lines)

    /// A new hand was dealt: how many cards the player holds (a fact, not the cards).
    static func newHand(count: Int) -> String { uiLocalized("machiavelli.say.newhand", count) }

    /// An opponent laid one or more combinations. Titles are the combinations that
    /// appeared; if none could be identified, a plain "laid N cards".
    static func opponentMelded(name: String, titles: [String], placed: Int, rearranged: Bool) -> String {
        if titles.isEmpty {
            return uiLocalized("machiavelli.say.opp.placed", name, placed)
        }
        let list = titles.joined(separator: ", ")
        return rearranged
            ? uiLocalized("machiavelli.say.opp.recomposed", name, list)
            : uiLocalized("machiavelli.say.opp.melded", name, list)
    }

    static func opponentDrew(name: String) -> String { uiLocalized("machiavelli.say.opp.drew", name) }

    /// End-of-hand scores, in seat order: "fine mano. tu 24 punti, giocatore 2 15 punti."
    static func handScores(entries: [(name: String, points: Int)]) -> String {
        let parts = entries.map { uiLocalized("machiavelli.say.score.entry", $0.name, $0.points) }
        return uiLocalized("machiavelli.say.handend", parts.joined(separator: ", "))
    }

    /// Match result from the human's point of view.
    static func matchResult(heroWon: Bool, winnerName: String) -> String {
        heroWon ? uiLocalized("machiavelli.say.match.won")
                : uiLocalized("machiavelli.say.match.lost", winnerName)
    }

    // MARK: - Voice slots (ClockTower speaker, informative → synthesis fallback)

    /// The ClockTower speaker sound for a moment, with its register fallback KEY (spoken
    /// via synthesis until the mp3 exists, D-030). Character/gender undecided (D-072).
    enum Cue { case handStart, yourTurn, meld, drew, passed, handEnd, matchEnd }

    static func voice(_ cue: Cue) -> (sound: SoundID, fallbackKey: String) {
        switch cue {
        case .handStart: return (SoundCatalog.voClockHandStart, "machiavelli.voice.handstart")
        case .yourTurn:  return (SoundCatalog.voClockYourTurn,  "machiavelli.voice.yourturn")
        case .meld:      return (SoundCatalog.voClockMeld,      "machiavelli.voice.meld")
        case .drew:      return (SoundCatalog.voClockDrew,      "machiavelli.voice.drew")
        case .passed:    return (SoundCatalog.voClockPassed,    "machiavelli.voice.passed")
        case .handEnd:   return (SoundCatalog.voClockHandEnd,   "machiavelli.voice.handend")
        case .matchEnd:  return (SoundCatalog.voClockMatchEnd,  "machiavelli.voice.matchend")
        }
    }

    // MARK: - Italian grammar helpers (variant-key approach, as D-045)

    private static func plural(_ r: Rank) -> String { uiLocalized("card.rank.plural.\(r.rawValue)") }
    private static func singular(_ r: Rank) -> String { uiLocalized("card.rank.\(r.rawValue)") }

    /// "dal cinque" / "dall'asso" / "dalla donna" — the "from the X" fragment of a run,
    /// with the article chosen by the rank (vowel elision for asso/otto; feminine for
    /// donna). English's variants collapse to the base ("from the X").
    private static func dalRank(_ r: Rank) -> String { uiLocalized(prepKey("machiavelli.prep.dal", r), singular(r)) }
    private static func alRank(_ r: Rank) -> String { uiLocalized(prepKey("machiavelli.prep.al", r), singular(r)) }

    private static func prepKey(_ base: String, _ r: Rank) -> String {
        if r == .queen { return base + ".fem" }        // donna
        if r == .ace || r == .eight { return base + ".vowel" }  // asso, otto
        return base
    }
}
