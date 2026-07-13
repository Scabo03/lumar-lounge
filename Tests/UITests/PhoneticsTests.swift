import XCTest

/// Poker-term VoiceOver pronunciation on the Italian voice (Alice).
///
/// After THREE failed attempts on the same word (D-049 "reis", D-054 the guardian,
/// D-059 IPA), the anchoring principle is now **D-060: a rendering is only "correct"
/// once it has been HEARD on the target voice.** A static test can never hear the TTS,
/// so this file no longer asserts that an invented grapheme is right (that false
/// assumption is exactly what passed green over a live bug three times). Instead it:
///   1. pins the EAR-VERIFIED renderings EXACTLY (each byte-identical to a synthesized
///      sample the user approved);
///   2. keeps the structural wiring guard (labels come from `.a11y` keys);
///   3. tracks the still-unverified catalog terms as a change-detector — never claiming
///      they are correct, only flagging a change so it gets re-verified by ear.
final class PhoneticsTests: XCTestCase {

    /// The Italian strings table, parsed straight from the source `.strings` file.
    private func italianStrings() throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Resources/it.lproj/Localizable.strings")
        let dict = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String],
                                 "could not load it.lproj/Localizable.strings at \(url.path)")
        return dict
    }

    // MARK: - D-060: the EAR-VERIFIED renderings (heard on Alice, byte-identical to the approved samples)

    /// These were confirmed by ACTUAL LISTENING to the it VoiceOver voice (Alice), each
    /// byte-identical to the audio sample the user approved. They are plain graphemes,
    /// NO IPA (the IPA path was unproven on device). Do NOT change a value here without
    /// re-verifying it by ear and re-approving the sound — that is the whole point of D-060.
    ///   • raise → the plain English word "Raise" (the invented "reis" was read "ace")
    ///   • fold  → "fohld", pronounced /ˈfold/ (the invented "fould" was read "Fohold")
    func testEarVerifiedButtonRenderings() throws {
        let s = try italianStrings()
        XCTAssertEqual(s["action.raise.a11y"], "Raise", "Texas Raise button — ear-verified render")
        XCTAssertEqual(s["raise.title.raise.a11y"], "Raise", "Raise box value element — same word, ear-verified")
        XCTAssertEqual(s["draw.action.raise.a11y"], "Raise a %d", "Draw Raise button — ear-verified render")
        XCTAssertEqual(s["action.fold.a11y"], "fohld", "Fold button — ear-verified render (/ˈfold/, no doubling)")
        XCTAssertTrue((s["raise.confirm.a11y"] ?? "").contains("Raise"),
                      "Raise confirm button — the same ear-verified word")
        // The failed renderings must not creep back.
        for key in ["action.raise.a11y", "raise.title.raise.a11y", "draw.action.raise.a11y",
                    "action.fold.a11y", "raise.confirm.a11y"] {
            let v = (s[key] ?? "").lowercased()
            XCTAssertFalse(v.contains("reis"), "\(key) reverted to the failed grapheme \"reis\" (reads \"ace\")")
            XCTAssertFalse(v.contains("fould"), "\(key) reverted to the failed grapheme \"fould\" (reads \"Fohold\")")
        }
    }

    // MARK: - Structural: every action-bar accessibility label comes from a `.a11y` key (D-054)

    func testActionBarAccessibilityLabelsUsePhoneticKeys() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for rel in ["UI/ActionBarView.swift", "UI/DrawActionBarView.swift"] {
            let src = try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            let keys = accessibilityLabelKeys(in: src)
            XCTAssertFalse(keys.isEmpty, "\(rel): found no accessibility-label keys to check — did the scan break?")
            for key in keys {
                XCTAssertTrue(key.hasSuffix(".a11y"),
                    "\(rel): accessibility label uses \"\(key)\", a VISIBLE-title key read aloud by "
                    + "VoiceOver. Use its dedicated \".a11y\" sibling (D-054).")
            }
        }
    }

    // MARK: - D-060: catalog terms NOT yet acoustically verified — change-detector only

    /// The CURRENT shipping renderings of the other poker terms. They are NOT confirmed
    /// by ear yet (pending the catalog listening pass), so this test claims nothing about
    /// their correctness — it only detects a change, so that whoever changes one is forced
    /// to re-verify it by ear and promote it to the ear-verified anchor above (D-060).
    func testUnverifiedCatalogTermsUnchangedPendingAcousticCheck() throws {
        let s = try italianStrings()
        let current: [String: String] = [
            "action.check.a11y": "cek",
            "action.call.a11y": "col",
            "raise.title.bet.a11y": "bett",
            "raise.allin.a11y": "ol-in",
            "seat.a11y.button": "bàtton",
            "seat.a11y.smallBlind": "smòl blaind",
            "seat.a11y.bigBlind": "big blaind",
            "seat.a11y.allIn": "ol-in",
            "seat.a11y.folded": "fould",     // narration (untouched this turn) — pending its own check
            "announce.opp.fold": "foulda",   // narration — pending
            "draw.action.bet.a11y": "bett",
        ]
        for (key, token) in current {
            let value = try XCTUnwrap(s[key], "missing string for \(key)")
            XCTAssertTrue(value.lowercased().contains(token.lowercased()),
                "\(key) = \"\(value)\" changed from \"\(token)\" — re-verify by ear, then move it to "
                + "the ear-verified anchor (D-060). Do not assert an un-heard rendering.")
        }
    }

    // MARK: - Source-scanning helpers

    /// The localization keys that become a VoiceOver accessibility LABEL in a source file.
    private func accessibilityLabelKeys(in src: String) -> [String] {
        var keys: [String] = []
        let ns = src as NSString
        let a11yArg = try! NSRegularExpression(pattern: #"a11yLabel:\s*uiLocalized\(\s*"([^"]+)""#)
        for m in a11yArg.matches(in: src, range: NSRange(location: 0, length: ns.length)) {
            keys.append(ns.substring(with: m.range(at: 1)))
        }
        for line in src.split(separator: "\n", omittingEmptySubsequences: false)
        where line.contains(".accessibilityLabel(") {
            keys += localizedKeys(in: String(line))
        }
        for body in functionBodies(whereName: { $0.hasSuffix("Label") }, in: src) {
            keys += localizedKeys(in: body)
        }
        return keys
    }

    private func localizedKeys(in text: String) -> [String] {
        let rx = try! NSRegularExpression(pattern: #"uiLocalized\(\s*"([^"]+)""#)
        let ns = text as NSString
        return rx.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    private func functionBodies(whereName predicate: (String) -> Bool, in src: String) -> [String] {
        var bodies: [String] = []
        let ns = src as NSString
        let open = UInt16(UInt8(ascii: "{")), close = UInt16(UInt8(ascii: "}"))
        let decl = try! NSRegularExpression(pattern: #"func\s+(\w+)\s*\("#)
        for m in decl.matches(in: src, range: NSRange(location: 0, length: ns.length)) {
            guard predicate(ns.substring(with: m.range(at: 1))) else { continue }
            var i = m.range.location + m.range.length
            while i < ns.length && ns.character(at: i) != open { i += 1 }
            guard i < ns.length else { continue }
            let start = i
            var depth = 0
            while i < ns.length {
                let c = ns.character(at: i)
                if c == open { depth += 1 }
                else if c == close { depth -= 1; if depth == 0 { i += 1; break } }
                i += 1
            }
            bodies.append(ns.substring(with: NSRange(location: start, length: i - start)))
        }
        return bodies
    }
}
