// SoundCatalog.swift
// =====================================================================
// The manifest of every sound the game can play: a logical name → file name +
// category. This is the ONE place to reconcile with the user's audio catalog
// (Lumar_Lounge_audio_catalog_M1.8.md).
//
// Names here match that catalog exactly (M1.8): the 47 delivered mp3 files were
// imported into `Resources/Audio/` and renamed to the catalog form where they
// differed (typos fixed, `_01` suffixes normalised). Six catalog sounds were not
// delivered (see `missing`); they are still listed so they play automatically if
// added later, and are reported at startup meanwhile. Missing files degrade to
// silence — see `AudioEngine`.

import Foundation

public enum SoundCatalog {

    // MARK: Ambient (8)
    public static let ambLoungeCalm1 = SoundID("amb_lounge_calm_01")
    public static let ambLoungeCalm2 = SoundID("amb_lounge_calm_02")
    public static let ambLoungeTense = SoundID("amb_lounge_tense_01")
    public static let ambCrowdDistant = SoundID("amb_crowd_distant")     // not delivered
    public static let ambSilenceTension = SoundID("amb_silence_tension")
    /// M2.1 world ambients — NOT delivered yet; each falls back to a lounge_calm
    /// bed until the real files are produced (D-035, D-028 fallback via missing→silent).
    public static let ambHomeNeutral = SoundID("amb_home_neutral")           // not delivered
    public static let ambRiverwoodCalm1 = SoundID("amb_riverwood_calm_01")   // not delivered
    public static let ambRiverwoodCalm2 = SoundID("amb_riverwood_calm_02")   // not delivered

    // MARK: UI (10)
    public static let uiButtonTap = SoundID("ui_button_tap")
    public static let uiButtonTapSoft = SoundID("ui_button_tap_soft")
    public static let uiBoxOpen = SoundID("ui_box_open")
    public static let uiBoxClose = SoundID("ui_box_close")
    public static let uiRaisePlus = SoundID("ui_raise_plus")
    public static let uiRaiseMinus = SoundID("ui_raise_minus")
    public static let uiAllInTrigger = SoundID("ui_all_in_trigger")
    public static let uiConfirm = SoundID("ui_confirm")
    public static let uiCancel = SoundID("ui_cancel")
    /// Screen-to-screen transition blip — NOT delivered yet (silent fallback, D-035).
    public static let uiNavigation = SoundID("ui_navigation")                // not delivered

    // MARK: Table (9)
    public static let tblCardDealSingle = SoundID("tbl_card_deal_single")
    public static let tblCardFlipSingle = SoundID("tbl_card_flip_single")
    public static let tblCardsDealFlop = SoundID("tbl_cards_deal_flop")
    public static let tblChipsSingle = SoundID("tbl_chips_single")
    public static let tblChipsStack = SoundID("tbl_chips_stack")
    public static let tblChipsBetLarge = SoundID("tbl_chips_bet_large")
    public static let tblChipsPotCollect = SoundID("tbl_chips_pot_collect")
    public static let tblMuck = SoundID("tbl_muck")
    public static let tblShuffle = SoundID("tbl_shuffle")

    // MARK: Croupier voices — Italian (16)
    public static let voYourTurn = SoundID("vo_it_your_turn")
    public static let voHandStart = SoundID("vo_it_hand_start")
    public static let voBlindSmall = SoundID("vo_it_blind_small")
    public static let voBlindBig = SoundID("vo_it_blind_big")
    /// Human-is-on-the-button role cue. NOT delivered yet → covered by a synthesis
    /// fallback ("sei sul bàtton") declared in the UI mapping (D-030).
    public static let voRoleButton = SoundID("vo_it_role_button")
    /// Fast-table decisive-hand cue — NOT delivered yet → synthesis fallback
    /// "mano decisiva" declared in the UI mapping (D-037/D-030).
    public static let voHighStakes = SoundID("vo_it_high_stakes")
    public static let voFlop = SoundID("vo_it_flop")
    public static let voTurn = SoundID("vo_it_turn")
    public static let voRiver = SoundID("vo_it_river")
    public static let voShowdown = SoundID("vo_it_showdown")
    public static let voActionFold = SoundID("vo_it_action_fold")
    public static let voActionCheck = SoundID("vo_it_action_check")
    public static let voActionCall = SoundID("vo_it_action_call")
    public static let voActionRaise = SoundID("vo_it_action_raise")
    public static let voActionAllIn = SoundID("vo_it_action_all_in")
    public static let voPotAwarded = SoundID("vo_it_pot_awarded")
    public static let voSplitPot = SoundID("vo_it_split_pot")

    // MARK: Croupier voices — Five-Card Draw (5, NOT delivered yet)
    // Each declares a VoiceOver synthesis fallback in the UI mapping (D-030), so it
    // speaks until the mp3 is produced and dropped into Resources/Audio/.
    public static let voAnte = SoundID("vo_it_ante")                         // not delivered
    public static let voDrawPhase = SoundID("vo_it_draw_phase")              // not delivered
    public static let voPassAndOut = SoundID("vo_it_pass_and_out")           // not delivered
    public static let voCarriedPot = SoundID("vo_it_carried_pot")            // not delivered
    public static let voOpenersDisqualified = SoundID("vo_it_openers_disqualified") // not delivered
    /// Whiskey-table decisive-hand cue (D-053) — NOT delivered yet → synthesis
    /// fallback "mano decisiva" declared in the UI mapping (D-030).
    public static let voHighStakesDraw = SoundID("vo_it_high_stakes_draw")   // not delivered

    // MARK: Bot voices (7)
    public static let vobNoviceExcited = SoundID("vob_novice_excited_01")
    public static let vobNoviceDisappointed = SoundID("vob_novice_disappointed_01")
    public static let vobNoviceNervous = SoundID("vob_novice_nervous_01")
    public static let vobRockGrunt = SoundID("vob_rock_grunt_01")
    public static let vobAggressorConfident = SoundID("vob_aggressor_confident_01")
    public static let vobAggressorTaunt = SoundID("vob_aggressor_taunt_01")
    public static let vobAggressorBluffGiveaway = SoundID("vob_aggressor_bluff_giveaway_01")

    // MARK: Outcome feedback (8)
    public static let fxWinHand = SoundID("fx_win_hand")
    public static let fxLoseHand = SoundID("fx_lose_hand")
    public static let fxHandNeutral = SoundID("fx_hand_neutral")          // not delivered
    public static let fxAllInDramatic = SoundID("fx_all_in_dramatic")
    public static let fxBustPlayer = SoundID("fx_bust_player")
    public static let fxBustHero = SoundID("fx_bust_hero")
    public static let fxVictoryFinal = SoundID("fx_victory_final")
    public static let fxDefeatFinal = SoundID("fx_defeat_final")

    /// Every sound with its category — used to preload and to report which files
    /// are missing from the bundle at startup.
    public static let all: [(id: SoundID, category: SoundCategory)] = [
        (ambLoungeCalm1, .ambient), (ambLoungeCalm2, .ambient), (ambLoungeTense, .ambient),
        (ambCrowdDistant, .ambient), (ambSilenceTension, .ambient),
        (ambHomeNeutral, .ambient), (ambRiverwoodCalm1, .ambient), (ambRiverwoodCalm2, .ambient),
        (uiButtonTap, .ui), (uiButtonTapSoft, .ui), (uiBoxOpen, .ui), (uiBoxClose, .ui),
        (uiRaisePlus, .ui), (uiRaiseMinus, .ui), (uiAllInTrigger, .ui), (uiConfirm, .ui), (uiCancel, .ui),
        (uiNavigation, .ui),
        (tblCardDealSingle, .table), (tblCardFlipSingle, .table), (tblCardsDealFlop, .table),
        (tblChipsSingle, .table), (tblChipsStack, .table), (tblChipsBetLarge, .table),
        (tblChipsPotCollect, .table), (tblMuck, .table), (tblShuffle, .table),
        (voYourTurn, .croupier), (voHandStart, .croupier), (voBlindSmall, .croupier), (voBlindBig, .croupier),
        (voRoleButton, .croupier), (voHighStakes, .croupier),
        (voFlop, .croupier), (voTurn, .croupier), (voRiver, .croupier), (voShowdown, .croupier),
        (voActionFold, .croupier), (voActionCheck, .croupier), (voActionCall, .croupier),
        (voActionRaise, .croupier), (voActionAllIn, .croupier), (voPotAwarded, .croupier), (voSplitPot, .croupier),
        (voAnte, .croupier), (voDrawPhase, .croupier), (voPassAndOut, .croupier),
        (voCarriedPot, .croupier), (voOpenersDisqualified, .croupier), (voHighStakesDraw, .croupier),
        (vobNoviceExcited, .botVoice), (vobNoviceDisappointed, .botVoice), (vobNoviceNervous, .botVoice),
        (vobRockGrunt, .botVoice), (vobAggressorConfident, .botVoice), (vobAggressorTaunt, .botVoice),
        (vobAggressorBluffGiveaway, .botVoice),
        (fxWinHand, .effect), (fxLoseHand, .effect), (fxHandNeutral, .effect), (fxAllInDramatic, .effect),
        (fxBustPlayer, .effect), (fxBustHero, .effect), (fxVictoryFinal, .effect), (fxDefeatFinal, .effect),
    ]
}
