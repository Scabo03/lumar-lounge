import XCTest

/// Verifies the curated Italian phonetic renders of the canonical poker terms
/// (D-049). Reads the real `it.lproj/Localizable.strings` from disk (the `.strings`
/// bundle isn't loaded under `swift test`) and checks that every accessibility
/// label / spoken string that names a poker term uses its phonetic spelling — so
/// the Italian VoiceOver voice pronounces it correctly (e.g. "reis", never "Raise",
/// which it reads as "Ace").
final class PhoneticsTests: XCTestCase {

    /// The Italian strings table, parsed straight from the source `.strings` file.
    private func italianStrings() throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let url = root.appendingPathComponent("Resources/it.lproj/Localizable.strings")
        let dict = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String],
                                 "could not load it.lproj/Localizable.strings at \(url.path)")
        return dict
    }

    // MARK: - The Raise bug (D-049): the raise-box label must be phonetic, not "Raise"

    func testRaiseBoxAccessibilityLabelIsPhonetic() throws {
        let s = try italianStrings()
        XCTAssertEqual(s["raise.title.raise.a11y"], "reis",
                       #"the raise-box VoiceOver label must be "reis" (Italian reads "Raise" as "Ace")"#)
        XCTAssertEqual(s["raise.title.bet.a11y"], "bett")
    }

    // MARK: - Canonical phonetic table for the spoken/a11y renders

    func testCanonicalPokerTermsAreRenderedPhonetically() throws {
        let s = try italianStrings()
        // key → the phonetic token that MUST appear in the (Italian) spoken value.
        let expected: [String: String] = [
            "action.fold.a11y": "fould",
            "action.check.a11y": "cek",
            "action.call.a11y": "col",
            "action.raise.a11y": "reis",
            "raise.title.raise.a11y": "reis",
            "raise.title.bet.a11y": "bett",
            "raise.allin.a11y": "ol-in",
            "raise.confirm.a11y": "reis",
            "seat.a11y.button": "bàtton",
            "seat.a11y.smallBlind": "smòl blaind",
            "seat.a11y.bigBlind": "big blaind",
            "seat.a11y.allIn": "ol-in",
            "seat.a11y.folded": "fould",
            "announce.opp.fold": "foulda",
            "announce.role.button": "bàtton",
            "draw.action.raise.a11y": "reis",
            "draw.action.bet.a11y": "bett",
        ]
        for (key, token) in expected {
            let value = try XCTUnwrap(s[key], "missing string for \(key)")
            XCTAssertTrue(value.lowercased().contains(token.lowercased()),
                          "\(key) = \"\(value)\" should contain the phonetic \"\(token)\"")
        }
    }

    // MARK: - Guard: no spoken label leaks the raw English "raise"/"ace"

    func testNoAccessibilityLabelLeaksTheRawRaiseWord() throws {
        let s = try italianStrings()
        // Keys whose value is READ ALOUD by VoiceOver (accessibility labels + the
        // synthesis announcements). Visible-only keys (button titles) are exempt.
        let spoken = s.filter { key, _ in
            key.hasSuffix(".a11y") || key.hasPrefix("announce.") || key.hasPrefix("draw.announce.")
        }
        for (key, value) in spoken {
            let lower = value.lowercased()
            XCTAssertFalse(lower.contains("raise"),
                           #"spoken \#(key) = "\#(value)" leaks the raw word "raise" (reads as "Ace")"#)
            // "fold" without the phonetic 'u' would be mispronounced; every spoken
            // occurrence must be "fould"/"foulda".
            if lower.contains("fold") {
                XCTAssertTrue(lower.contains("fould"),
                              #"spoken \#(key) = "\#(value)" uses "fold" instead of the phonetic "fould""#)
            }
        }
    }

    // MARK: - D-054: the pronunciation guard extends to UI BUTTONS, not just spoken strings

    /// The recurring bug (D-049, then again D-054): a poker button was read by its
    /// VISIBLE English title ("Raise" → "Ace") because a visible-title localization
    /// key was wired as the accessibility LABEL. This scans the two action-bar sources
    /// and asserts that every key that ends up as a VoiceOver accessibility label uses
    /// its phonetic `.a11y` sibling — covering the UI elements, not only the strings.
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
                    + "VoiceOver (e.g. \"Raise\"→\"Ace\"). Use its phonetic \".a11y\" sibling (D-054).")
            }
        }
    }

    /// The localization keys that become a VoiceOver accessibility LABEL in a source
    /// file: the key passed as the `a11yLabel:` argument (only that argument — a
    /// same-line `title:` visible key must NOT be swept in), every key inside a
    /// `.accessibilityLabel(...)` line, and every key returned by the label-producing
    /// helper funcs (name ends in "Label").
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

    /// The `uiLocalized("KEY")` keys referenced in a fragment of source.
    private func localizedKeys(in text: String) -> [String] {
        let rx = try! NSRegularExpression(pattern: #"uiLocalized\(\s*"([^"]+)""#)
        let ns = text as NSString
        return rx.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    /// The bodies of funcs whose name satisfies `predicate`, extracted by brace match.
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
