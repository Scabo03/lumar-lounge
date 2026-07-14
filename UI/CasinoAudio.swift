// CasinoAudio.swift
// =====================================================================
// The audio PALETTE of a casino (D-067): its croupier voice + register, its ambient
// beds, and its bots' colour voices. The croupier is an attribute of the CASINO, not
// of the game — one croupier for all a casino's tables (Texas, Draw, Omaha, anything
// future). This is what a blind player uses to tell one casino from another: they
// don't see the marble or the felt, they HEAR the voice and the air. If the Skypool's
// Texas sounded like the Riverwood's, the two casinos would be the same place for them,
// and the narrative progression the project wants would vanish (accessibility, "nobody
// loses anything").
//
// The design keeps the RIVERWOOD as the IDENTITY / DEFAULT palette: an empty croupier
// remap, empty register overrides, and the exact lounge beds + `vob_` voices used
// today. So routing the Riverwood through this layer is byte-identical by construction
// — the regression guard (`CasinoAudioRegressionTests`) pins it. A new casino declares
// its palette HERE (data), and all its tables inherit that croupier without anyone
// touching the speech maps, the conductor, or the directors.
//
// This lives in UI: it knows both the concrete `SoundCatalog` ids (Audio) and the
// casino registry (GameWorld). The `Audio` module stays game- and casino-agnostic.

import Foundation
import GameWorld
import Audio

/// A casino's ambient beds. Each is a (preferred, fallback) pair; the director plays
/// the preferred one if its file is bundled, else the fallback (D-030/D-066).
public struct AmbientBeds: Equatable, Sendable {
    public let calm1: SoundID,  calm1Fallback: SoundID
    public let calm2: SoundID,  calm2Fallback: SoundID
    public let tense: SoundID,  tenseFallback: SoundID
    public let layer: SoundID,  layerFallback: SoundID
    /// Playback gain (0…1) of the continuous background layer. Per-casino because a
    /// real layer's inherent loudness varies: the Skypool's pool/water bed is a very
    /// quiet undertone, well below the Riverwood's distant-crowd layer (D-069).
    public let layerVolume: Float

    /// The Riverwood/default beds — EXACTLY what the Texas `AudioDirector` plays today
    /// (lounge beds, distant crowd layer at 0.2). Preferred == fallback, all already
    /// bundled, so nothing changes for the Riverwood (D-067 regression).
    public static let riverwood = AmbientBeds(
        calm1: SoundCatalog.ambLoungeCalm1, calm1Fallback: SoundCatalog.ambLoungeCalm1,
        calm2: SoundCatalog.ambLoungeCalm2, calm2Fallback: SoundCatalog.ambLoungeCalm2,
        tense: SoundCatalog.ambLoungeTense, tenseFallback: SoundCatalog.ambLoungeTense,
        layer: SoundCatalog.ambCrowdDistant, layerFallback: SoundCatalog.ambCrowdDistant,
        layerVolume: 0.2)

    /// The Skypool beds — cool urban stone/water. The water layer is kept a BARE
    /// whisper (0.02) after two listening passes found it too loud even at 0.05 — from
    /// the original 0.18/0.2 that is ~-19 dB, a faint undertone (D-069); it falls back
    /// to the distant-crowd bed until the StableAudio file is produced.
    public static let skypool = AmbientBeds(
        calm1: SoundCatalog.ambSkypoolCalm1, calm1Fallback: SoundCatalog.ambLoungeCalm1,
        calm2: SoundCatalog.ambSkypoolCalm2, calm2Fallback: SoundCatalog.ambLoungeCalm2,
        tense: SoundCatalog.ambSkypoolTense, tenseFallback: SoundCatalog.ambLoungeTense,
        layer: SoundCatalog.ambSkypoolWater, layerFallback: SoundCatalog.ambCrowdDistant,
        layerVolume: 0.02)

    /// The ClockTower beds (D-072) — erudite CLASSICAL music (strings), calm_01/02 two
    /// crossfaded movements, `tense` the searching passage played while a bot thinks
    /// (the audible wait), a continuous low grandfather-clock TICK as the layer. None
    /// produced yet → each falls back to a lounge bed; the clock layer is a quiet
    /// undertone (0.12).
    public static let clocktower = AmbientBeds(
        calm1: SoundCatalog.ambClocktowerCalm1, calm1Fallback: SoundCatalog.ambLoungeCalm1,
        calm2: SoundCatalog.ambClocktowerCalm2, calm2Fallback: SoundCatalog.ambLoungeCalm2,
        tense: SoundCatalog.ambClocktowerThinking, tenseFallback: SoundCatalog.ambLoungeTense,
        layer: SoundCatalog.ambClocktowerClock, layerFallback: SoundCatalog.ambCrowdDistant,
        layerVolume: 0.12)
}

/// A casino's bots' colour voices (`vob_`). AMBIENT: a missing file falls back to
/// silence, never synthesis (D-066).
public struct BotVoices: Equatable, Sendable {
    public let noviceExcited: SoundID
    public let noviceDisappointed: SoundID
    public let noviceNervous: SoundID
    public let rockGrunt: SoundID
    public let aggressorConfident: SoundID
    public let aggressorTaunt: SoundID
    public let aggressorBluffGiveaway: SoundID

    /// The Riverwood/default `vob_` set — exactly today's voices (D-067 regression).
    public static let riverwood = BotVoices(
        noviceExcited: SoundCatalog.vobNoviceExcited,
        noviceDisappointed: SoundCatalog.vobNoviceDisappointed,
        noviceNervous: SoundCatalog.vobNoviceNervous,
        rockGrunt: SoundCatalog.vobRockGrunt,
        aggressorConfident: SoundCatalog.vobAggressorConfident,
        aggressorTaunt: SoundCatalog.vobAggressorTaunt,
        aggressorBluffGiveaway: SoundCatalog.vobAggressorBluffGiveaway)

    /// The Skypool urban `vob_` set — silent until produced (ambient fallback, D-066).
    public static let skypool = BotVoices(
        noviceExcited: SoundCatalog.vobSkyNoviceExcited,
        noviceDisappointed: SoundCatalog.vobSkyNoviceDisappointed,
        noviceNervous: SoundCatalog.vobSkyNoviceNervous,
        rockGrunt: SoundCatalog.vobSkyRockGrunt,
        aggressorConfident: SoundCatalog.vobSkyAggressorConfident,
        aggressorTaunt: SoundCatalog.vobSkyAggressorTaunt,
        aggressorBluffGiveaway: SoundCatalog.vobSkyAggressorBluffGiveaway)
}

/// The full audio palette of a casino.
public struct CasinoAudio {
    public let id: String
    /// Remaps a DEFAULT (game-produced) croupier SoundID to THIS casino's SoundID.
    /// Empty for the default palette (identity).
    private let croupierRemap: [String: SoundID]
    /// The register FALLBACK localization key per THIS casino's croupier SoundID, spoken
    /// when the mp3 isn't bundled yet (D-030). `nil`/absent → no casino override, so the
    /// speech map's own declared fallback (if any) is used instead — which keeps the
    /// Riverwood identical.
    private let fallbackKeys: [String: String]
    public let ambient: AmbientBeds
    public let botVoices: BotVoices

    public init(id: String, croupierRemap: [String: SoundID] = [:], fallbackKeys: [String: String] = [:],
                ambient: AmbientBeds, botVoices: BotVoices) {
        self.id = id
        self.croupierRemap = croupierRemap
        self.fallbackKeys = fallbackKeys
        self.ambient = ambient
        self.botVoices = botVoices
    }

    /// Resolves a default croupier SoundID to THIS casino's actual (sound, register
    /// fallback KEY). The fallback key is nil when the casino declares no override — the
    /// caller then uses the speech map's own fallback (Riverwood behaviour).
    public func croupier(_ defaultID: SoundID?) -> (sound: SoundID?, fallbackKey: String?) {
        guard let defaultID else { return (nil, nil) }
        let mapped = croupierRemap[defaultID.rawValue] ?? defaultID
        return (mapped, fallbackKeys[mapped.rawValue])
    }

    // MARK: - The palettes

    /// The Riverwood — the DEFAULT/IDENTITY palette. Empty remap + empty overrides +
    /// today's lounge beds and `vob_` voices → routing the Riverwood through this layer
    /// is byte-identical (D-067). A game's speech map already produces the Riverwood
    /// croupier ids and its own fallbacks; this changes nothing for it.
    public static let riverwood = CasinoAudio(
        id: "riverwood", croupierRemap: [:], fallbackKeys: [:],
        ambient: .riverwood, botVoices: .riverwood)

    /// The Skypool — its OWN croupier (cooler, cynical, urban register), remapping every
    /// default croupier cue to a `vo_it_sky_*` voice with a register fallback key, plus
    /// the Skypool beds and urban `vob_`. None of the mp3s exist yet, so every croupier
    /// line speaks the register FALLBACK (informative → synthesis, D-066).
    public static let skypool = CasinoAudio(
        id: "skypool",
        croupierRemap: [
            SoundCatalog.voHandStart.rawValue:    SoundCatalog.voSkyHandStart,
            SoundCatalog.voBlindSmall.rawValue:   SoundCatalog.voSkyBlindSmall,
            SoundCatalog.voBlindBig.rawValue:     SoundCatalog.voSkyBlindBig,
            SoundCatalog.voRoleButton.rawValue:   SoundCatalog.voSkyRoleButton,
            SoundCatalog.voYourTurn.rawValue:     SoundCatalog.voSkyYourTurn,
            SoundCatalog.voFlop.rawValue:         SoundCatalog.voSkyFlop,
            SoundCatalog.voTurn.rawValue:         SoundCatalog.voSkyTurn,
            SoundCatalog.voRiver.rawValue:        SoundCatalog.voSkyRiver,
            SoundCatalog.voShowdown.rawValue:     SoundCatalog.voSkyShowdown,
            SoundCatalog.voActionAllIn.rawValue:  SoundCatalog.voSkyActionAllIn,
            SoundCatalog.voPotAwarded.rawValue:   SoundCatalog.voSkyPotAwarded,
            SoundCatalog.voSplitPot.rawValue:     SoundCatalog.voSkySplitPot,
            SoundCatalog.voHighStakes.rawValue:   SoundCatalog.voSkyStakesUp,
        ],
        fallbackKeys: [
            // handStart stays a chime → no fallback text (silent, like the Riverwood).
            SoundCatalog.voSkyBlindSmall.rawValue:  "skypool.croupier.blind.small",
            SoundCatalog.voSkyBlindBig.rawValue:    "skypool.croupier.blind.big",
            SoundCatalog.voSkyRoleButton.rawValue:  "skypool.croupier.button",
            SoundCatalog.voSkyYourTurn.rawValue:    "skypool.croupier.yourturn",
            SoundCatalog.voSkyFlop.rawValue:        "skypool.croupier.flop",
            SoundCatalog.voSkyTurn.rawValue:        "skypool.croupier.turn",
            SoundCatalog.voSkyRiver.rawValue:       "skypool.croupier.river",
            SoundCatalog.voSkyShowdown.rawValue:    "skypool.croupier.showdown",
            SoundCatalog.voSkyActionAllIn.rawValue: "skypool.croupier.allin",
            SoundCatalog.voSkyPotAwarded.rawValue:  "skypool.croupier.pot",
            SoundCatalog.voSkySplitPot.rawValue:    "skypool.croupier.split",
            SoundCatalog.voSkyStakesUp.rawValue:    "skypool.croupier.stakesup",
        ],
        ambient: .skypool, botVoices: .skypool)

    /// The ClockTower (D-072). Its ambient is the erudite classical MUSIC; its "speaker"
    /// voice (turns, combinations, scores) is NOT the poker croupier, so it needs no
    /// croupier remap — `MachiavelliSpeechMap` produces the ClockTower `vo_it_clock_*`
    /// ids and their synthesis fallbacks directly (as the Draw map does for the
    /// Riverwood, D-067). The `botVoices` field (poker-shaped) is UNUSED by Machiavelli,
    /// which uses its own colour voices in `MachiavelliAudioDirector`; the Riverwood set
    /// is a harmless placeholder here.
    public static let clockTower = CasinoAudio(
        id: "clocktower", croupierRemap: [:], fallbackKeys: [:],
        ambient: .clocktower, botVoices: .riverwood)

    /// Every casino's palette, keyed by casino id. Adding a casino = adding an entry
    /// HERE (declaring its palette). The speech maps / conductor / directors are never
    /// touched — the third casino inherits its croupier by construction (D-067).
    public static let registry: [String: CasinoAudio] = [
        "riverwood": .riverwood,
        "skypool": .skypool,
        "clocktower": .clockTower,
    ]

    /// The palette for a casino id (default Riverwood for an unknown/nil id).
    public static func of(casinoID: String?) -> CasinoAudio {
        registry[casinoID ?? ""] ?? .riverwood
    }

    /// The palette of the casino that HOSTS a table — the one line that ties a table to
    /// its casino's voice, so all of a casino's tables share one croupier (D-067).
    public static func hosting(table id: String) -> CasinoAudio {
        of(casinoID: Casinos.casino(hosting: id)?.id)
    }
}
