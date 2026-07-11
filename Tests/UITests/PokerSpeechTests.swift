import XCTest
import Accessibility
@testable import UI

/// The Raise buttons' pronunciation is specified by explicit IPA, not a guessed
/// grapheme (D-059). The previous "reis" transliteration was applied correctly yet
/// still read "ace" by the Italian voice; a grapheme is not a reliable spec of a
/// sound, and no static test can HEAR one. IPA is a standardized, unambiguous spec,
/// so these tests pin the pronunciation deterministically — the regression that
/// survived two sessions cannot recur silently.
final class PokerSpeechTests: XCTestCase {

    /// IPA notations present on the runs of an attributed string.
    private func ipaRuns(_ s: AttributedString) -> [String] {
        s.runs.compactMap { s[$0.range].accessibilitySpeechPhoneticNotation }
    }

    func testRaiseIPAIsTheCanonicalRaiseSound() {
        // /ˈreɪz/ is the sound of "raise"; if it ever changes, it changes HERE.
        XCTAssertEqual(PokerSpeech.raiseIPA, "ˈreɪz")
    }

    func testTexasRaiseLabelCarriesTheRaiseIPA() {
        let label = PokerSpeech.raiseLabel(spelled: "reis")
        XCTAssertEqual(String(label.characters), "reis", "the base/spelled fallback text")
        XCTAssertEqual(ipaRuns(label), ["ˈreɪz"], "the word is pronounced by explicit IPA, not the grapheme")
    }

    func testDrawRaiseLabelIPAOnlyOnTheWordNotTheNumber() {
        let label = PokerSpeech.raiseLabel(spelled: "reis", amount: " a 40")
        XCTAssertEqual(String(label.characters), "reis a 40", "base text = word + plain amount tail")
        // Exactly one run is IPA-annotated (the word); the " a 40" tail is pronounced
        // normally, so the number never corrupts the word's pronunciation.
        XCTAssertEqual(ipaRuns(label), ["ˈreɪz"])
    }

    func testAnnotateSetsThePhoneticNotation() {
        let s = PokerSpeech.annotate("whatever", ipa: "təˈmɑːtoʊ")
        XCTAssertEqual(s.accessibilitySpeechPhoneticNotation, "təˈmɑːtoʊ")
    }
}
