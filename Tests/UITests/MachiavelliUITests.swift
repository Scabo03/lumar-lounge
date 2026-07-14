// MachiavelliUITests.swift
// =====================================================================
// The Machiavelli UI layer (D-072): the ClockTower's cheap addition to the casino
// registry, the workspace's hypothetical/repeatable turn model, the single validity
// predicate queried identically by the box and by drag, the describe-not-advise
// selection read-out, and the meld titles — all in the pure `swift test` layer.

import XCTest
@testable import UI
import GameWorld
import GameEngine
import Audio

final class MachiavelliUITests: XCTestCase {

    private func c(_ r: Rank, _ s: Suit) -> Card { Card(r, s) }

    // MARK: - ClockTower added to the registry cheaply (generalisation held — D-072)

    func testClockTowerIsInTheRegistryAsADataChange() {
        XCTAssertTrue(Casinos.all.contains { $0.id == "clocktower" })
        let clock = Casinos.clockTower
        XCTAssertEqual(clock.tables.count, 1)
        let table = clock.tables[0]
        XCTAssertEqual(table.id, "clocktower.table.machiavelli")
        if case .machiavelli = table.game {} else { XCTFail("the ClockTower's table is Machiavelli") }
    }

    func testAddingTheClockTowerNeededNoAudioPathChange() {
        // The palette resolves purely from the registry (D-067): a new casino inherits
        // the whole audio path by DATA, no speech-map/conductor/director change.
        let palette = CasinoAudio.hosting(table: "clocktower.table.machiavelli")
        XCTAssertEqual(palette.id, "clocktower")
        XCTAssertEqual(CasinoAudio.of(casinoID: "clocktower").id, "clocktower")
    }

    func testRiverwoodAndSkypoolUntouched() {
        // Same tables, same buy-ins as before the ClockTower arrived.
        XCTAssertEqual(Casinos.riverwood.tables.map { $0.id },
                       ["riverwood.table.classic", "riverwood.table.fast", "riverwood.table.draw"])
        XCTAssertEqual(Casinos.skypool.tables.map { $0.buyIn }, [5000, 6000, 10000])
        XCTAssertEqual(CasinoAudio.of(casinoID: "riverwood").id, "riverwood")
        XCTAssertEqual(CasinoAudio.of(casinoID: "skypool").id, "skypool")
    }

    // MARK: - The single validity predicate, queried by BOX and by DRAG (D-072)

    func testBoxGateIsExactlyTheEnginePredicate() {
        let ws = MachiavelliWorkspace(hand: [c(.eight, .spades), c(.eight, .hearts), c(.eight, .diamonds)], table: [])
        // The three 8s (hand indices 0,1,2).
        XCTAssertEqual(ws.selectionIsLegalCombination([0, 1, 2]),
                       MachiavelliRules.classify([c(.eight, .spades), c(.eight, .hearts), c(.eight, .diamonds)]) != nil)
        XCTAssertTrue(ws.selectionIsLegalCombination([0, 1, 2]))
        // Two 8s are not a legal combination — the box gate agrees with the engine.
        XCTAssertEqual(ws.selectionIsLegalCombination([0, 1]),
                       MachiavelliRules.classify([c(.eight, .spades), c(.eight, .hearts)]) != nil)
        XCTAssertFalse(ws.selectionIsLegalCombination([0, 1]))
    }

    func testBoxAndDragReachTheSameValidStateViaTheSamePredicate() {
        let hand = [c(.eight, .spades), c(.eight, .hearts), c(.eight, .diamonds)]

        // BOX path: select all three, confirm once.
        var boxWS = MachiavelliWorkspace(hand: hand, table: [])
        boxWS.placeCombination([0, 1, 2])

        // DRAG path: drag them one at a time into a new group (transiently invalid).
        var dragWS = MachiavelliWorkspace(hand: hand, table: [])
        dragWS.moveToGroup(0, groupIndex: nil)
        XCTAssertFalse(dragWS.tableIsValid, "one card is a transiently INVALID table (allowed)")
        dragWS.moveToGroup(1, groupIndex: 0)
        XCTAssertFalse(dragWS.tableIsValid, "two cards still invalid")
        dragWS.moveToGroup(2, groupIndex: 0)

        // Both reach the SAME valid table, both judged by MachiavelliRules.isValidTable.
        XCTAssertTrue(boxWS.tableIsValid)
        XCTAssertTrue(dragWS.tableIsValid)
        XCTAssertEqual(Set(boxWS.meldCards.map { Set($0) }), Set(dragWS.meldCards.map { Set($0) }))
        XCTAssertTrue(boxWS.canPass)
        XCTAssertTrue(dragWS.canPass)
    }

    // MARK: - Hypothetical + repeatable turn (D-072)

    func testPlacingReducesHandOnlyOnConfirm() {
        var ws = MachiavelliWorkspace(hand: [c(.two, .spades), c(.two, .hearts), c(.two, .diamonds), c(.king, .clubs)], table: [])
        XCTAssertEqual(ws.placedCount, 0)
        XCTAssertTrue(ws.mustDraw)
        XCTAssertFalse(ws.canPass)
        ws.placeCombination([0, 1, 2])          // confirm the three 2s
        XCTAssertEqual(ws.placedCount, 3)
        XCTAssertTrue(ws.canPass)
        XCTAssertFalse(ws.mustDraw)
    }

    func testTerminalGatesOnValidityNotJustPlacement() {
        var ws = MachiavelliWorkspace(hand: [c(.eight, .spades), c(.eight, .hearts), c(.king, .clubs)], table: [])
        ws.moveToGroup(0, groupIndex: nil)      // 8♠ alone — placed, but table invalid
        ws.moveToGroup(1, groupIndex: 0)        // 8♠8♥ — two cards, still invalid
        XCTAssertGreaterThan(ws.placedCount, 0)
        XCTAssertFalse(ws.canPass, "placed cards but the table is invalid → cannot pass")
    }

    func testSameCardCanBeReusedWithinTheTurn() {
        // Place 9♣ into a group of 9s, then move a 9 into the heart run — recomposing,
        // and retract the just-placed hand card back and forth.
        var ws = MachiavelliWorkspace(
            hand: [c(.nine, .clubs)],
            table: [[c(.nine, .spades), c(.nine, .hearts), c(.nine, .diamonds)],
                    [c(.six, .hearts), c(.seven, .hearts), c(.eight, .hearts)]])
        // Retract/replace the hand card: place it, retract to hand, place again.
        let handIndex = 0
        ws.moveToGroup(handIndex, groupIndex: 0)        // 9♣ joins the 9s (group of four)
        XCTAssertEqual(ws.placedCount, 1)
        ws.retractToHand(handIndex)                     // take it back
        XCTAssertEqual(ws.placedCount, 0)
        ws.moveToGroup(handIndex, groupIndex: 0)        // place it again — same card, same turn
        XCTAssertEqual(ws.placedCount, 1)
        XCTAssertTrue(ws.tableIsValid)
    }

    func testTableCardIsNeverPocketed() {
        // A table-origin card cannot be retracted to hand (conservation, D-070).
        var ws = MachiavelliWorkspace(hand: [c(.two, .clubs)],
                                      table: [[c(.five, .spades), c(.six, .spades), c(.seven, .spades)]])
        let tableCardIndex = 1   // hand has index 0; table cards start at 1
        let before = ws.placedCount
        ws.retractToHand(tableCardIndex)
        XCTAssertEqual(ws.placedCount, before, "a table card is never moved into the hand")
    }

    // MARK: - Meld titles (branch selection — bundle-independent, D-072)

    func testMeldTitleClassifiesTrisPokerRun() {
        // Under `swift test` uiLocalized returns the KEY, so we assert which branch fired.
        XCTAssertEqual(MachiavelliSpeechMap.meldTitle([c(.ace, .spades), c(.ace, .hearts), c(.ace, .diamonds)]),
                       "machiavelli.meld.tris")
        XCTAssertEqual(MachiavelliSpeechMap.meldTitle([c(.king, .spades), c(.king, .hearts), c(.king, .diamonds), c(.king, .clubs)]),
                       "machiavelli.meld.poker")
        XCTAssertEqual(MachiavelliSpeechMap.meldTitle([c(.five, .spades), c(.six, .spades), c(.seven, .spades)]),
                       "machiavelli.meld.run")
        XCTAssertNil(MachiavelliSpeechMap.meldTitle([c(.five, .spades), c(.six, .hearts)]))
    }

    // MARK: - Selection read-out DESCRIBES, never ADVISES (D-072)

    func testSelectionReadOutDescribesStateWithoutAdvising() {
        XCTAssertEqual(MachiavelliSpeechMap.describeSelection([]), "machiavelli.sel.none")
        // A valid combination states the fact.
        XCTAssertEqual(MachiavelliSpeechMap.describeSelection([c(.five, .hearts), c(.six, .hearts), c(.seven, .hearts)]),
                       "machiavelli.sel.valid")
        // A partial same-suit selection is an "incomplete run" — description, not advice.
        XCTAssertEqual(MachiavelliSpeechMap.describeSelection([c(.five, .hearts), c(.seven, .hearts), c(.nine, .hearts)]),
                       "machiavelli.sel.samesuit.run")
        // A same-rank partial.
        XCTAssertEqual(MachiavelliSpeechMap.describeSelection([c(.five, .hearts), c(.five, .spades)]),
                       "machiavelli.sel.samerank")
        // A loose mix.
        XCTAssertEqual(MachiavelliSpeechMap.describeSelection([c(.five, .hearts), c(.king, .spades)]),
                       "machiavelli.sel.loose")
        // The read-out NEVER names a completing card (only the six declared keys are used).
        let declared: Set<String> = ["machiavelli.sel.none", "machiavelli.sel.valid", "machiavelli.sel.samerank",
                                     "machiavelli.sel.samesuit", "machiavelli.sel.samesuit.run", "machiavelli.sel.loose"]
        XCTAssertTrue(declared.contains(MachiavelliSpeechMap.describeSelection([c(.two, .clubs), c(.three, .diamonds), c(.nine, .hearts)])))
    }

    // MARK: - Per-game ambient bed at the ClockTower (D-073)

    func testClockTowerAmbientDependsOnTheGame() {
        let palette = CasinoAudio.clockTower
        // Machiavelli gets the CLOCKWORK bed (long cognitive turn on the audio channel).
        XCTAssertEqual(palette.ambient(forGame: "machiavelli").calm1, SoundCatalog.ambClocktowerMachiavelli1)
        // The casino default (future poker tables) is the CLASSICAL strings bed.
        XCTAssertEqual(palette.ambient(forGame: "texas").calm1, SoundCatalog.ambClocktowerCalm1)
        XCTAssertEqual(palette.ambient.calm1, SoundCatalog.ambClocktowerCalm1)
    }

    func testRiverwoodAndSkypoolHaveNoPerGameBed() {
        // They declare no override, so any game resolves to their single casino bed.
        XCTAssertEqual(CasinoAudio.riverwood.ambient(forGame: "machiavelli").calm1, CasinoAudio.riverwood.ambient.calm1)
        XCTAssertEqual(CasinoAudio.skypool.ambient(forGame: "texas").calm1, CasinoAudio.skypool.ambient.calm1)
    }

    // MARK: - Broken-combination declaration: DECLARE the state, never ADVISE (D-073)

    func testKnobDeclaresBrokenOnlyWhenInvalid() {
        // A valid combination reads as its title; a broken one declares itself incomplete.
        XCTAssertEqual(MachiavelliSpeechMap.knobTitle([c(.five, .spades), c(.six, .spades), c(.seven, .spades)]),
                       "machiavelli.meld.run")
        XCTAssertEqual(MachiavelliSpeechMap.knobTitle([c(.seven, .spades), c(.seven, .hearts)]),
                       "machiavelli.broken.samerank")   // two 7s — an incomplete tris
        XCTAssertEqual(MachiavelliSpeechMap.knobTitle([c(.three, .spades), c(.five, .spades)]),
                       "machiavelli.broken.samesuit")   // spades, not consecutive — a broken run
        XCTAssertEqual(MachiavelliSpeechMap.knobTitle([c(.three, .spades), c(.king, .hearts)]),
                       "machiavelli.broken.generic")
    }

    func testBrokenDeclarationNeverAdvises() {
        // The guardian: the broken declaration only ever uses the three declared keys —
        // none of which names a missing card or where to take it (description, not advice).
        let declared: Set<String> = ["machiavelli.broken.samerank", "machiavelli.broken.samesuit",
                                     "machiavelli.broken.generic"]
        let cases: [[Card]] = [
            [c(.seven, .spades), c(.seven, .hearts)],
            [c(.three, .spades), c(.five, .spades), c(.nine, .spades)],
            [c(.two, .clubs), c(.king, .hearts), c(.nine, .diamonds)],
            [c(.ace, .spades), c(.ace, .hearts), c(.ace, .spades)],   // dup suit — invalid group
        ]
        for cards in cases { XCTAssertTrue(declared.contains(MachiavelliSpeechMap.brokenTitle(cards))) }
    }

    func testInvalidTableWithPlacementAlwaysExposesABrokenCombination() {
        // The "no stuck without information" guarantee, at the logic level: whenever the
        // player has placed a card but cannot pass, the table carries a nameable broken
        // combination — so `passBlockedReason` always has something to declare.
        var ws = MachiavelliWorkspace(hand: [c(.eight, .spades), c(.eight, .hearts), c(.eight, .diamonds)],
                                      table: [[c(.five, .spades), c(.six, .spades), c(.seven, .spades)]])
        ws.placeCombination([0, 1, 2])                 // lay the three 8s (placed 3, valid)
        XCTAssertTrue(ws.canPass)
        ws.moveToGroup(3, groupIndex: nil)             // pull 5♠ out — the run is now broken
        XCTAssertFalse(ws.canPass)
        XCTAssertGreaterThan(ws.placedCount, 0)
        let broken = ws.meldCards.filter { MachiavelliRules.classify($0) == nil }
        XCTAssertFalse(broken.isEmpty, "a blocked pass always has a broken combination to name")
    }

    func testValidTableHasNoBrokenCombination() {
        var ws = MachiavelliWorkspace(hand: [c(.eight, .spades), c(.eight, .hearts), c(.eight, .diamonds)], table: [])
        ws.placeCombination([0, 1, 2])
        XCTAssertTrue(ws.canPass)
        XCTAssertTrue(ws.meldCards.allSatisfy { MachiavelliRules.classify($0) != nil })
    }

    // MARK: - The composition box RIBBON (D-074): a linear, structured sequence

    func testBoxRibbonIsHandThenTitledCombinations() {
        let hand = [MachiavelliChainCard(index: 0, card: c(.two, .clubs), isHand: true),
                    MachiavelliChainCard(index: 1, card: c(.king, .hearts), isHand: true)]
        let group0 = [MachiavelliChainCard(index: 2, card: c(.five, .spades), isHand: false),
                      MachiavelliChainCard(index: 3, card: c(.six, .spades), isHand: false),
                      MachiavelliChainCard(index: 4, card: c(.seven, .spades), isHand: false)]
        let group1 = [MachiavelliChainCard(index: 5, card: c(.ace, .spades), isHand: false),
                      MachiavelliChainCard(index: 6, card: c(.ace, .hearts), isHand: false),
                      MachiavelliChainCard(index: 7, card: c(.ace, .diamonds), isHand: false)]
        let box = MachiavelliBoxState(handCards: hand, tableGroups: [group0, group1], selected: [4, 2])

        // The ribbon runs: hand cards, then each combination's cards, in order.
        XCTAssertEqual(box.allCards.map { $0.index }, [0, 1, 2, 3, 4, 5, 6, 7])
        // Each combination's divider announces the SAME title as its table-edge knob.
        XCTAssertEqual(MachiavelliSpeechMap.knobTitle(group0.map { $0.card }), "machiavelli.meld.run")
        XCTAssertEqual(MachiavelliSpeechMap.knobTitle(group1.map { $0.card }), "machiavelli.meld.tris")
        // The pool reads in selection order (the zone with the "selected" marker).
        XCTAssertEqual(box.poolEntries.map { $0.index }, [4, 2])
        XCTAssertEqual(box.selectedCards, [c(.seven, .spades), c(.five, .spades)])
    }

    // MARK: - Ribbon jump gesture: anchors and the two extremes (D-075)

    func testRibbonJumpAnchorsAndExtremes() {
        let hand = [MachiavelliChainCard(index: 0, card: c(.two, .clubs), isHand: true)]
        let group0 = [MachiavelliChainCard(index: 1, card: c(.five, .spades), isHand: false)]
        let group1 = [MachiavelliChainCard(index: 2, card: c(.six, .spades), isHand: false)]
        let box = MachiavelliBoxState(handCards: hand, tableGroups: [group0, group1], selected: [])

        // Anchors: 0 = "tavolo", 1 = first combination, 2 = second combination.
        XCTAssertEqual(box.dividerCount, 3)
        // Forward jumps stop at the last combination.
        XCTAssertEqual(box.nextDivider(from: 0), 1)
        XCTAssertEqual(box.nextDivider(from: 1), 2)
        XCTAssertNil(box.nextDivider(from: 2), "no next past the last combination — clamped")
        // Backward jumps stop at the "tavolo" divider.
        XCTAssertEqual(box.previousDivider(from: 2), 1)
        XCTAssertEqual(box.previousDivider(from: 1), 0)
        XCTAssertNil(box.previousDivider(from: 0), "no previous before the tavolo divider — clamped")
    }

    // MARK: - Announcement discipline: close events serialize, never truncate (D-074)

    @MainActor
    func testCloseMeldAnnouncementsSerializeInOrderWithoutTruncation() async {
        // The queue the Machiavelli table now shares with the poker tables (D-032/D-074):
        // several combination announcements arriving close together are spoken serially,
        // in order, with none truncated by the next.
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = false            // no VoiceOver → drains in order, synchronously
        var spoken: [String] = []
        queue.synthesisObserver = { spoken.append($0) }
        queue.enqueue("il Professore cala tris di assi", priority: .medium)
        queue.enqueue("il Bibliotecario cala scala di picche dal cinque al dieci", priority: .medium)
        queue.enqueue("lo Studente pesca dal tallone", priority: .medium)
        await Task.yield()
        XCTAssertEqual(spoken.count, 3, "every close announcement is spoken — none truncated")
        XCTAssertEqual(spoken.first, "il Professore cala tris di assi")
    }

    // MARK: - Every Machiavelli localization key used actually exists (real text ships)

    func testMachiavelliKeysExistInItalian() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Resources/it.lproj/Localizable.strings")
        let strings = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        let required = [
            "clocktower.tagline", "home.clocktower.blurb", "endgame.return.clocktower",
            "table.machiavelli.title", "table.machiavelli.room",
            "machiavelli.meld.tris", "machiavelli.meld.poker", "machiavelli.meld.run",
            "machiavelli.prep.dal", "machiavelli.prep.dal.vowel", "machiavelli.prep.dal.fem",
            "machiavelli.prep.al", "machiavelli.prep.al.vowel", "machiavelli.prep.al.fem",
            "machiavelli.sel.none", "machiavelli.sel.valid", "machiavelli.sel.samerank",
            "machiavelli.sel.samesuit", "machiavelli.sel.samesuit.run", "machiavelli.sel.loose",
            "machiavelli.voice.yourturn", "machiavelli.say.opp.melded", "machiavelli.say.handend",
            "machiavelli.box.pool", "machiavelli.box.chain", "machiavelli.box.tabledivider",
            "machiavelli.box.confirm", "machiavelli.action.piazza", "machiavelli.action.pass",
            "machiavelli.action.draw", "machiavelli.knob.card", "machiavelli.card.a11y.selected",
            "machiavelli.name.you", "machiavelli.name.student", "machiavelli.name.professor",
            "machiavelli.broken.samerank", "machiavelli.broken.samesuit", "machiavelli.broken.generic",
            "machiavelli.pass.blocked.nothing", "machiavelli.pass.blocked.invalid", "machiavelli.pass.blocked",
        ]
        for key in required { XCTAssertNotNil(strings[key], "missing it.lproj key: \(key)") }
    }
}
