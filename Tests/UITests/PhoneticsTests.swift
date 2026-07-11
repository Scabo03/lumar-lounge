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
}
