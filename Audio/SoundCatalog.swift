// SoundCatalog.swift
// =====================================================================
// The manifest of every sound the game can play: a logical name → file name +
// category. This is the ONE place to reconcile with the user's real audio
// catalog (Lumar_Lounge_audio_catalog_M1.8.md) — edit the `SoundID` strings
// here to match the delivered file names and everything downstream follows.
//
// ⚠️ PROVISIONAL NAMES (M1.8): the real catalog and the 47 mp3 files were not
// present on the machine when this module was built, so the file names below
// are inferred from the brief's examples (ui_button_tap, vo_it_flop,
// vob_novice_disappointed_01, vob_aggressor_confident_01, fx_win_hand,
// fx_all_in_dramatic, amb_/tbl_ categories). Drop the mp3s into
// `Resources/Audio/` and adjust any names here that differ. Missing files are
// handled gracefully (silence + a startup log) — see `AudioEngine`.
//
// The `_01` suffixes are kept where a sound is expected to grow "02", "03"
// sibling variants later, as the user requested.

import Foundation

public enum SoundCatalog {

    // MARK: Ambient
    public static let ambientLounge = SoundID("amb_casino_lounge_01")

    // MARK: Table (physical, non-spoken)
    public static let cardDeal = SoundID("tbl_card_deal_01")
    public static let cardFlip = SoundID("tbl_card_flip_01")
    public static let chipsBet = SoundID("tbl_chips_bet_01")
    public static let chipsToPot = SoundID("tbl_chips_to_pot_01")
    public static let cardMuck = SoundID("tbl_card_muck_01")

    // MARK: Croupier voices (spoken, Italian)
    public static let voFlop = SoundID("vo_it_flop")
    public static let voTurn = SoundID("vo_it_turn")
    public static let voRiver = SoundID("vo_it_river")
    public static let voAllIn = SoundID("vo_it_all_in")
    public static let voShowdown = SoundID("vo_it_showdown")

    // MARK: Bot voices (spoken) — keyed to the M1.7 roster personalities
    public static let vobNoviceHappy = SoundID("vob_novice_happy_01")
    public static let vobNoviceDisappointed = SoundID("vob_novice_disappointed_01")
    public static let vobRockConfident = SoundID("vob_rock_confident_01")
    public static let vobRockDisappointed = SoundID("vob_rock_disappointed_01")
    public static let vobAggressorConfident = SoundID("vob_aggressor_confident_01")
    public static let vobAggressorDisappointed = SoundID("vob_aggressor_disappointed_01")

    // MARK: Dramatic effects (non-spoken)
    public static let fxAllInDramatic = SoundID("fx_all_in_dramatic")
    public static let fxWinHand = SoundID("fx_win_hand")
    public static let fxLoseHand = SoundID("fx_lose_hand")
    public static let fxWinGame = SoundID("fx_win_game")
    public static let fxLoseGame = SoundID("fx_lose_game")

    // MARK: UI feedback (non-spoken, played on user input)
    public static let uiButtonTap = SoundID("ui_button_tap")
    public static let uiRaiseStep = SoundID("ui_raise_step_01")

    /// Every sound with its category — used to preload and to report which
    /// files are missing from the bundle at startup.
    public static let all: [(id: SoundID, category: SoundCategory)] = [
        (ambientLounge, .ambient),
        (cardDeal, .table), (cardFlip, .table), (chipsBet, .table),
        (chipsToPot, .table), (cardMuck, .table),
        (voFlop, .croupier), (voTurn, .croupier), (voRiver, .croupier),
        (voAllIn, .croupier), (voShowdown, .croupier),
        (vobNoviceHappy, .botVoice), (vobNoviceDisappointed, .botVoice),
        (vobRockConfident, .botVoice), (vobRockDisappointed, .botVoice),
        (vobAggressorConfident, .botVoice), (vobAggressorDisappointed, .botVoice),
        (fxAllInDramatic, .effect), (fxWinHand, .effect), (fxLoseHand, .effect),
        (fxWinGame, .effect), (fxLoseGame, .effect),
        (uiButtonTap, .ui), (uiRaiseStep, .ui),
    ]
}
