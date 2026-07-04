# Resources/Audio — audio assets

The Lumar Lounge `.mp3` files live here (integrated in M1.8).

- This folder is inside the app target's **synchronized** `Resources` group, so
  every file here is automatically included in the app bundle — no Xcode project
  edit needed (verified: files land flat in the bundle root).
- File names match `Audio/SoundCatalog.swift`. The engine looks them up by name
  via `Bundle.main`.
- Missing files degrade gracefully: the app runs, that sound is silent, and the
  list of missing files is logged once at startup (`[Audio] N/M missing …`).

## Status (M1.8)

**47 of 53** cataloged sounds are present. On import they were renamed to the
catalog form where the delivered names differed (per the user's choice to align
to `Lumar_Lounge_audio_catalog_M1.8.md`): the `ui_botton_*` typos → `ui_button_*`,
`fx_all_in` → `fx_all_in_dramatic`, `tbl_card_shuffle` → `tbl_shuffle`,
`vo_it_new_hand` → `vo_it_hand_start`, `vo_it_pot_split` → `vo_it_split_pot`,
`vo_it_pot_winner` → `vo_it_pot_awarded`, and the seven `vob_*` got their `_01`
suffix. One delivered file not in the catalog (`tbl_card_distribution`) was not
imported.

**6 cataloged sounds were not delivered** (currently silent, logged at startup):
`amb_crowd_distant`, `fx_hand_neutral`, and the four chip sounds
`tbl_chips_single` / `tbl_chips_stack` / `tbl_chips_bet_large` /
`tbl_chips_pot_collect`. Drop them in here (matching those names) to complete the
set — no code change needed.

Categories (by file-name prefix): `amb_` ambient · `tbl_` table effects ·
`vo_it_` croupier voice (Italian) · `vob_` bot voices · `fx_` dramatic feedback ·
`ui_` UI input feedback.
