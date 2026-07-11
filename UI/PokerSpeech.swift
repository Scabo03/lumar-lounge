// PokerSpeech.swift
// =====================================================================
// Deterministic VoiceOver pronunciation for the poker-term buttons whose invented
// Italian transliteration the Italian VoiceOver voice mispronounces (D-059).
//
// Background: the spoken NARRATION says "rilancia" (a real Italian word) and is
// fine. The BUTTONS keep the English poker term visible ("Raise") and used to spell
// its pronunciation phonetically ("reis") in the localized `.a11y` string. That
// transliteration was applied correctly (verified: the button's runtime label IS
// "reis") but the Italian voice still reads it wrong ("ace"): a guessed grapheme is
// not a reliable spec of a sound. So instead of guessing letters we attach the exact
// IPA notation — a standardized, unambiguous spec of the SOUND — which VoiceOver
// honours regardless of grapheme. IPA cannot be "guessed wrong" the way a grapheme
// can, which is what let the bug survive two sessions and a green guardian.

import SwiftUI
import Accessibility

enum PokerSpeech {

    /// IPA for the English "raise" (/ˈreɪz/) — the sound both Raise buttons must
    /// produce. THE canonical pronunciation for "raise" (D-059); if it ever needs to
    /// change, change it here and in the catalog note in CONVENTIONS §4.
    static let raiseIPA = "ˈreɪz"

    /// Attaches an IPA pronunciation to `text`: VoiceOver speaks the run using the
    /// IPA, so the exact phonemes are produced no matter how `text` is spelled.
    static func annotate(_ text: String, ipa: String) -> AttributedString {
        var s = AttributedString(text)
        // The IPA-notation attribute (`IPANotationAttribute`) — VoiceOver pronounces
        // the run by these exact phonemes, ignoring the grapheme.
        s.accessibilitySpeechPhoneticNotation = ipa
        return s
    }

    /// The Texas Raise button's spoken label: the word, pronounced via IPA (D-059).
    /// `spelled` is what a braille display / spell mode shows and the fallback if IPA
    /// is unsupported; the sound is fixed by `raiseIPA`.
    static func raiseLabel(spelled: String) -> AttributedString {
        annotate(spelled, ipa: raiseIPA)
    }

    /// The Draw Raise button's spoken label: the IPA-pronounced word plus the fixed
    /// amount, composed as two runs so the number never bleeds into the word's
    /// pronunciation (D-059). `amount` is a plain, already-localized tail (e.g. " a 40").
    static func raiseLabel(spelled: String, amount: String) -> AttributedString {
        annotate(spelled, ipa: raiseIPA) + AttributedString(amount)
    }
}
