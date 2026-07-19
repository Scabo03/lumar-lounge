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

    /// Skypool ambient beds (D-066) — cool urban stone/water. NOT delivered yet; each
    /// falls back to a lounge bed until the real files are produced (StableAudio).
    public static let ambSkypoolCalm1 = SoundID("amb_skypool_calm_01")       // not delivered
    public static let ambSkypoolCalm2 = SoundID("amb_skypool_calm_02")       // not delivered
    public static let ambSkypoolTense = SoundID("amb_skypool_tense_01")      // not delivered
    /// A continuous low water/crowd layer for the Skypool (its pool). Not delivered →
    /// no layer (silent) until produced.
    public static let ambSkypoolWater = SoundID("amb_skypool_water_01")      // not delivered

    /// ClockTower ambience & MUSIC (D-072) — the first casino whose background has a
    /// FORM, not just an atmosphere: erudite CLASSICAL music (strings, complex
    /// articulated contrapuntal structure) over ancient stone, wood and books. NOT
    /// delivered yet (StableAudio); each falls back to a lounge bed until produced.
    /// calm_01/calm_02 are two movements crossfaded for variety; `thinking` is the
    /// more urgent, searching passage played while a bot deliberates (the audible wait,
    /// D-072); `clock` is the continuous low grandfather-clock tick undertone.
    public static let ambClocktowerCalm1 = SoundID("amb_clocktower_calm_01")     // not delivered
    public static let ambClocktowerCalm2 = SoundID("amb_clocktower_calm_02")     // not delivered
    public static let ambClocktowerThinking = SoundID("amb_clocktower_thinking_01") // not delivered
    public static let ambClocktowerClock = SoundID("amb_clocktower_clock_01")    // not delivered
    /// The ClockTower's MACHIAVELLI bed (D-073): the game's turn is LONG cognitive work
    /// done — for the blind player — ON THE AUDIO CHANNEL, so a bed with thematic
    /// development would COMPETE with the listening. Machiavelli therefore gets a
    /// CLOCKWORK bed instead: gears/mechanism, rhythmic and ambient, present without
    /// asking for attention, ARCHITECTURAL and VAST (an observatory/engine hall — the
    /// ClockTower is the largest-feeling of the three casinos). TWO tracks alternated by
    /// crossfade so a long match never loops audibly, each internally variable; a
    /// clockwork "thinking" variant fills the audible wait (gears intensifying). NOT
    /// delivered → falls back to a lounge bed.
    public static let ambClocktowerMachiavelli1 = SoundID("amb_clocktower_machiavelli_01")         // not delivered
    public static let ambClocktowerMachiavelli2 = SoundID("amb_clocktower_machiavelli_02")         // not delivered
    public static let ambClocktowerMachiavelliThinking = SoundID("amb_clocktower_machiavelli_thinking_01") // not delivered

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

    // MARK: Croupier voices — Skypool (D-066, NOT delivered yet)
    // The Skypool's own croupier — a distinct, cooler urban voice. None produced yet;
    // each is INFORMATIVE, so it falls back to VoiceOver synthesis (D-030) declared in
    // OmahaSpeechMap until the mp3 is dropped into Resources/Audio/ (ElevenLabs).
    public static let voSkyHandStart = SoundID("vo_it_sky_hand_start")            // not delivered
    public static let voSkyBlindSmall = SoundID("vo_it_sky_blind_small")          // not delivered
    public static let voSkyBlindBig = SoundID("vo_it_sky_blind_big")              // not delivered
    public static let voSkyRoleButton = SoundID("vo_it_sky_role_button")          // not delivered
    public static let voSkyYourTurn = SoundID("vo_it_sky_your_turn")              // not delivered
    public static let voSkyFlop = SoundID("vo_it_sky_flop")                       // not delivered
    public static let voSkyTurn = SoundID("vo_it_sky_turn")                       // not delivered
    public static let voSkyRiver = SoundID("vo_it_sky_river")                     // not delivered
    public static let voSkyShowdown = SoundID("vo_it_sky_showdown")               // not delivered
    public static let voSkyActionAllIn = SoundID("vo_it_sky_action_all_in")       // not delivered
    public static let voSkyPotAwarded = SoundID("vo_it_sky_pot_awarded")          // not delivered
    public static let voSkySplitPot = SoundID("vo_it_sky_split_pot")              // not delivered
    /// Omaha-specific: the croupier reminds the Pot Limit cap on the human's turn.
    public static let voSkyPotLimit = SoundID("vo_it_sky_pot_limit")              // not delivered
    /// Session acceleration (D-064): the blinds ratcheted up.
    public static let voSkyStakesUp = SoundID("vo_it_sky_stakes_up")              // not delivered

    // MARK: Bot voices — Skypool urban (D-066, NOT delivered yet)
    // AMBIENT colour of the three URBAN archetypes. Each is category `.botVoice`, so a
    // missing file falls back to SILENCE, never synthesis (D-066): a missing colour
    // line simply doesn't play — it must never become an intrusive announcement.
    public static let vobSkyNoviceExcited = SoundID("vob_sky_novice_excited_01")            // not delivered
    public static let vobSkyNoviceDisappointed = SoundID("vob_sky_novice_disappointed_01")  // not delivered
    public static let vobSkyNoviceNervous = SoundID("vob_sky_novice_nervous_01")            // not delivered
    public static let vobSkyRockGrunt = SoundID("vob_sky_rock_grunt_01")                    // not delivered
    public static let vobSkyAggressorConfident = SoundID("vob_sky_aggressor_confident_01")  // not delivered
    public static let vobSkyAggressorTaunt = SoundID("vob_sky_aggressor_taunt_01")          // not delivered
    public static let vobSkyAggressorBluffGiveaway = SoundID("vob_sky_aggressor_bluff_giveaway_01") // not delivered

    // MARK: The ClockTower "speaker" voice — Machiavelli (D-072, NOT delivered yet)
    // The ClockTower has no croupier: Machiavelli has no pot/bets/showdown. The figure
    // who speaks scans the TURNS, declares the COMBINATIONS laid, and announces the
    // end-of-hand SCORES, in an erudite, measured, learned register. The CHARACTER and
    // GENDER are STILL UNDECIDED (the user will decide before producing the voices) —
    // only the register is fixed. Each is INFORMATIVE, so it falls back to VoiceOver
    // synthesis (D-030) declared in `MachiavelliSpeechMap` until the mp3 is produced.
    public static let voClockHandStart = SoundID("vo_it_clock_hand_start")    // not delivered → content synth
    public static let voClockYourTurn = SoundID("vo_it_clock_your_turn")      // delivered (D-080)
    public static let voClockMeld = SoundID("vo_it_clock_meld")               // delivered (D-080, ex "combination")
    public static let voClockDrew = SoundID("vo_it_clock_drew")               // not delivered → content synth
    public static let voClockPassed = SoundID("vo_it_clock_passed")           // not delivered (unused)
    public static let voClockHandEnd = SoundID("vo_it_clock_hand_end")        // not delivered → scores synth
    public static let voClockMatchEnd = SoundID("vo_it_clock_match_end")      // delivered (D-080, ex "game_end")
    /// The "shift" cues (D-081): a turn that REARRANGES existing table combinations (not just
    /// adds a new one) — distinct from a plain meld. Two, by who did it (opponent / the human).
    public static let voClockOpponentShift = SoundID("vo_it_clock_opponent_shift")   // delivered (D-081)
    public static let voClockPlayerShift = SoundID("vo_it_clock_player_shift")        // delivered (D-081)

    // MARK: The ClockTower custode as POKER croupier — `vo_it_tower_*` (D-077/D-080)
    // The SAME old man who arbitrates the Machiavelli (`vo_it_clock_*`) is the croupier at
    // the ClockTower's poker tables (`vo_it_tower_*`), in an erudite, measured, ITALIAN
    // register. The user PRODUCED a generic-poker set; the ClockTower's only poker table so
    // far is Stud, which uses the cues below that map to its events. Missing cues fall back
    // to synthesis (D-030) or, per the ClockTower's LOWER verbosity, to silence (D-080).
    public static let voTowerNewHand = SoundID("vo_it_tower_new_hand")           // delivered → Stud hand start
    public static let voTowerShowdown = SoundID("vo_it_tower_showdown")          // delivered → Stud showdown
    public static let voTowerPotAwarded = SoundID("vo_it_tower_pot_awarded")     // delivered → Stud pot
    public static let voTowerSplitPot = SoundID("vo_it_tower_split_pot")         // delivered → Stud split pot
    public static let voTowerGameEnd = SoundID("vo_it_tower_game_end")           // delivered → Stud session end
    /// NOT delivered → synthesis fallback (an ESSENTIAL turn signal, kept for accessibility).
    public static let voTowerYourTurn = SoundID("vo_it_tower_your_turn")         // not delivered
    /// NOT delivered → synthesis fallback (the rare full-table-win reward line, D-079).
    public static let voTowerHousePrize = SoundID("vo_it_tower_house_prize")     // not delivered
    // Also delivered, but RESERVED for a future ClockTower Texas/community table (they map to
    // blinds/flop/turn/river/button/escalation, which Stud does not have): bundled in
    // Resources/Audio, unwired for now — `vo_it_tower_big_blind/small_blind/flop/turn/river/
    // role_button/stakes_rise`. Not catalogued (no table references them yet).

    // MARK: Bot voices — ClockTower archetypes (D-072, NOT delivered yet)
    // AMBIENT colour of the three learned archetypes (student, adult, professor). Each
    // is `.botVoice`, so a missing file falls back to SILENCE, never synthesis (D-066):
    // a missing colour line simply doesn't play. Used by `MachiavelliAudioDirector`.
    public static let vobClockStudentEager = SoundID("vob_clock_student_eager_01")             // not delivered
    public static let vobClockStudentPleased = SoundID("vob_clock_student_pleased_01")         // not delivered
    public static let vobClockAdultPonders = SoundID("vob_clock_adult_ponders_01")             // not delivered
    public static let vobClockAdultPleased = SoundID("vob_clock_adult_pleased_01")             // not delivered
    public static let vobClockProfessorMasterstroke = SoundID("vob_clock_professor_masterstroke_01") // not delivered
    public static let vobClockProfessorPleased = SoundID("vob_clock_professor_pleased_01")     // not delivered

    // MARK: Bot voices (7)
    public static let vobNoviceExcited = SoundID("vob_novice_excited_01")
    public static let vobNoviceDisappointed = SoundID("vob_novice_disappointed_01")
    public static let vobNoviceNervous = SoundID("vob_novice_nervous_01")
    public static let vobRockGrunt = SoundID("vob_rock_grunt_01")
    public static let vobAggressorConfident = SoundID("vob_aggressor_confident_01")
    public static let vobAggressorTaunt = SoundID("vob_aggressor_taunt_01")
    public static let vobAggressorBluffGiveaway = SoundID("vob_aggressor_bluff_giveaway_01")

    // MARK: Blackjack — croupier voice (D-090, NOT delivered yet)
    // Blackjack keeps the croupier deliberately QUIET: the game is fast and every
    // spoken line is time the player spends waiting. The only voice wired is the
    // shuffle, which lands roughly once every sixty rounds and explains a real
    // pause. Both carry a synthesis fallback (informative → D-030/D-066).
    public static let voBjShuffle = SoundID("vo_it_bj_shuffle")               // not delivered
    public static let voSkyBjShuffle = SoundID("vo_it_sky_bj_shuffle")        // not delivered

    // MARK: Blackjack — the presence of other players (D-090, NOT delivered yet)
    // There are no other players at the table mechanically: these are pure
    // ATMOSPHERE, so they are `.botVoice` (ambient) and fall back to SILENCE, never
    // to synthesis — an unproduced colour must never become an announcement that
    // interrupts a blind player's listening (D-066). Because no NPC ever speaks,
    // one shared set serves every casino.
    public static let fxBjPresenceChips = SoundID("fx_bj_presence_chips")     // not delivered
    public static let fxBjPresenceMurmur = SoundID("fx_bj_presence_murmur")   // not delivered
    public static let fxBjPresenceCards = SoundID("fx_bj_presence_cards")     // not delivered

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
        (ambSkypoolCalm1, .ambient), (ambSkypoolCalm2, .ambient), (ambSkypoolTense, .ambient), (ambSkypoolWater, .ambient),
        (ambClocktowerCalm1, .ambient), (ambClocktowerCalm2, .ambient),
        (ambClocktowerThinking, .ambient), (ambClocktowerClock, .ambient),
        (ambClocktowerMachiavelli1, .ambient), (ambClocktowerMachiavelli2, .ambient),
        (ambClocktowerMachiavelliThinking, .ambient),
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
        (voBjShuffle, .croupier), (voSkyBjShuffle, .croupier),
        (fxBjPresenceChips, .botVoice), (fxBjPresenceMurmur, .botVoice), (fxBjPresenceCards, .botVoice),
        (voAnte, .croupier), (voDrawPhase, .croupier), (voPassAndOut, .croupier),
        (voCarriedPot, .croupier), (voOpenersDisqualified, .croupier), (voHighStakesDraw, .croupier),
        (voSkyHandStart, .croupier), (voSkyBlindSmall, .croupier), (voSkyBlindBig, .croupier),
        (voSkyRoleButton, .croupier), (voSkyYourTurn, .croupier), (voSkyFlop, .croupier),
        (voSkyTurn, .croupier), (voSkyRiver, .croupier), (voSkyShowdown, .croupier),
        (voSkyActionAllIn, .croupier), (voSkyPotAwarded, .croupier), (voSkySplitPot, .croupier),
        (voSkyPotLimit, .croupier), (voSkyStakesUp, .croupier),
        (voClockHandStart, .croupier), (voClockYourTurn, .croupier), (voClockMeld, .croupier),
        (voClockDrew, .croupier), (voClockPassed, .croupier), (voClockHandEnd, .croupier), (voClockMatchEnd, .croupier),
        (voClockOpponentShift, .croupier), (voClockPlayerShift, .croupier),
        (voTowerNewHand, .croupier), (voTowerShowdown, .croupier), (voTowerPotAwarded, .croupier),
        (voTowerSplitPot, .croupier), (voTowerGameEnd, .croupier),
        (voTowerYourTurn, .croupier), (voTowerHousePrize, .croupier),
        (vobClockStudentEager, .botVoice), (vobClockStudentPleased, .botVoice),
        (vobClockAdultPonders, .botVoice), (vobClockAdultPleased, .botVoice),
        (vobClockProfessorMasterstroke, .botVoice), (vobClockProfessorPleased, .botVoice),
        (vobNoviceExcited, .botVoice), (vobNoviceDisappointed, .botVoice), (vobNoviceNervous, .botVoice),
        (vobRockGrunt, .botVoice), (vobAggressorConfident, .botVoice), (vobAggressorTaunt, .botVoice),
        (vobAggressorBluffGiveaway, .botVoice),
        (vobSkyNoviceExcited, .botVoice), (vobSkyNoviceDisappointed, .botVoice), (vobSkyNoviceNervous, .botVoice),
        (vobSkyRockGrunt, .botVoice), (vobSkyAggressorConfident, .botVoice), (vobSkyAggressorTaunt, .botVoice),
        (vobSkyAggressorBluffGiveaway, .botVoice),
        (fxWinHand, .effect), (fxLoseHand, .effect), (fxHandNeutral, .effect), (fxAllInDramatic, .effect),
        (fxBustPlayer, .effect), (fxBustHero, .effect), (fxVictoryFinal, .effect), (fxDefeatFinal, .effect),
    ]
}
