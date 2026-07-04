# Resources/Audio — audio assets

Drop the Lumar Lounge `.mp3` files here.

- This folder is inside the app target's **synchronized** `Resources` group, so
  any file placed here is automatically included in the app bundle — no Xcode
  project edit needed.
- File names must match the entries in `Audio/SoundCatalog.swift` (base name,
  `.mp3` extension). The engine looks them up by name via `Bundle.main`, trying
  both the bundle root and this `Audio/` subdirectory.
- Missing files degrade gracefully: the app runs, that sound is silent, and the
  full list of missing files is logged once at startup (`[Audio] … missing …`).
- The `_01` suffixes are kept where a sound is expected to gain `02`, `03`
  sibling variants later.

Categories (by file-name prefix): `amb_` ambient · `tbl_` table effects ·
`vo_it_` croupier voice (Italian) · `vob_` bot voices · `fx_` dramatic feedback ·
`ui_` UI input feedback.

> **M1.8 status:** the 47 catalog files were not on the machine when the Audio
> module was built, so `SoundCatalog.swift` uses PROVISIONAL names inferred from
> the brief. Reconcile those names with `Lumar_Lounge_audio_catalog_M1.8.md`
> when the files are available, then place the mp3s here.
