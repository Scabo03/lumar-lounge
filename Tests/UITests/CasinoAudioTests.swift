import XCTest
@testable import UI
import GameWorld
import Audio

/// The croupier + ambient palette as an attribute of the CASINO, not the game (D-067).
/// The most important test here is the REGRESSION pin: the Riverwood palette is the
/// IDENTITY palette, so routing the Riverwood through the casino audio layer changes
/// nothing — same croupier ids, no register overrides, the exact lounge beds and `vob_`.
@MainActor
final class CasinoAudioTests: XCTestCase {

    // Every default croupier cue a game's speech map can emit.
    private let croupierCues: [SoundID] = [
        SoundCatalog.voHandStart, SoundCatalog.voBlindSmall, SoundCatalog.voBlindBig,
        SoundCatalog.voRoleButton, SoundCatalog.voYourTurn, SoundCatalog.voFlop,
        SoundCatalog.voTurn, SoundCatalog.voRiver, SoundCatalog.voShowdown,
        SoundCatalog.voActionAllIn, SoundCatalog.voPotAwarded, SoundCatalog.voSplitPot,
        SoundCatalog.voHighStakes,
    ]

    // MARK: - REGRESSION: the Riverwood is the identity palette (D-067)

    func testRiverwoodPaletteIsIdentity() {
        let r = CasinoAudio.riverwood
        for cue in croupierCues {
            let (sound, fallback) = r.croupier(cue)
            XCTAssertEqual(sound, cue, "Riverwood must not remap the croupier voice for \(cue.rawValue)")
            XCTAssertNil(fallback, "Riverwood must declare NO register override for \(cue.rawValue) "
                         + "(the speech map's own fallback is used, so behaviour is unchanged)")
        }
        // The exact lounge beds + vob_ voices the Texas director plays today.
        XCTAssertEqual(r.ambient, .riverwood)
        XCTAssertEqual(r.botVoices, .riverwood)
        XCTAssertEqual(AmbientBeds.riverwood.calm1, SoundCatalog.ambLoungeCalm1)
        XCTAssertEqual(AmbientBeds.riverwood.calm2, SoundCatalog.ambLoungeCalm2)
        XCTAssertEqual(AmbientBeds.riverwood.tense, SoundCatalog.ambLoungeTense)
        XCTAssertEqual(BotVoices.riverwood.noviceExcited, SoundCatalog.vobNoviceExcited)
        XCTAssertEqual(BotVoices.riverwood.aggressorConfident, SoundCatalog.vobAggressorConfident)
    }

    // MARK: - The Skypool has its OWN croupier + register + ambient (D-067)

    func testSkypoolPaletteRemapsEveryCroupierCueToItsOwnVoiceWithRegister() {
        let s = CasinoAudio.skypool
        let expected: [(SoundID, SoundID, String)] = [
            (SoundCatalog.voHandStart,   SoundCatalog.voSkyHandStart,   ""),  // chime → no fallback
            (SoundCatalog.voBlindSmall,  SoundCatalog.voSkyBlindSmall,  "skypool.croupier.blind.small"),
            (SoundCatalog.voBlindBig,    SoundCatalog.voSkyBlindBig,    "skypool.croupier.blind.big"),
            (SoundCatalog.voRoleButton,  SoundCatalog.voSkyRoleButton,  "skypool.croupier.button"),
            (SoundCatalog.voYourTurn,    SoundCatalog.voSkyYourTurn,    "skypool.croupier.yourturn"),
            (SoundCatalog.voFlop,        SoundCatalog.voSkyFlop,        "skypool.croupier.flop"),
            (SoundCatalog.voTurn,        SoundCatalog.voSkyTurn,        "skypool.croupier.turn"),
            (SoundCatalog.voRiver,       SoundCatalog.voSkyRiver,       "skypool.croupier.river"),
            (SoundCatalog.voShowdown,    SoundCatalog.voSkyShowdown,    "skypool.croupier.showdown"),
            (SoundCatalog.voActionAllIn, SoundCatalog.voSkyActionAllIn, "skypool.croupier.allin"),
            (SoundCatalog.voPotAwarded,  SoundCatalog.voSkyPotAwarded,  "skypool.croupier.pot"),
            (SoundCatalog.voSplitPot,    SoundCatalog.voSkySplitPot,    "skypool.croupier.split"),
            (SoundCatalog.voHighStakes,  SoundCatalog.voSkyStakesUp,    "skypool.croupier.stakesup"),
        ]
        for (defaultID, skyID, key) in expected {
            let (sound, fallback) = s.croupier(defaultID)
            XCTAssertEqual(sound, skyID, "Skypool must use its own voice for \(defaultID.rawValue)")
            XCTAssertEqual(fallback, key.isEmpty ? nil : key, "register fallback for \(defaultID.rawValue)")
        }
        // The Omaha map already emits vo_it_sky_* ids; the palette leaves them and still
        // supplies the register fallback (keyed by the casino's own SoundID).
        XCTAssertEqual(s.croupier(SoundCatalog.voSkyFlop).sound, SoundCatalog.voSkyFlop)
        XCTAssertEqual(s.croupier(SoundCatalog.voSkyFlop).fallbackKey, "skypool.croupier.flop")
        XCTAssertEqual(s.ambient, .skypool)
        XCTAssertEqual(s.botVoices, .skypool)
    }

    // MARK: - Skypool uses its palette on ALL its tables — Texas AND Omaha (D-067)

    func testEverySkypoolTableResolvesToTheSkypoolPalette() {
        for table in Casinos.skypool.tables {
            XCTAssertEqual(CasinoAudio.hosting(table: table.id).id, "skypool",
                           "\(table.id) must use the Skypool croupier — Texas and Omaha alike")
        }
        for table in Casinos.riverwood.tables {
            XCTAssertEqual(CasinoAudio.hosting(table: table.id).id, "riverwood",
                           "\(table.id) must keep the Riverwood croupier")
        }
    }

    // MARK: - A new casino inherits the mechanism WITHOUT touching the audio path (D-067)

    func testPaletteResolutionIsDataDrivenSoANewCasinoInheritsForFree() {
        // The resolution is pure data: a casino's palette is looked up by id, and the
        // croupier remap/fallback are applied generically — no per-casino code in the
        // speech maps, conductor or directors. A brand-new palette resolves the same way.
        let newCasino = CasinoAudio(
            id: "velvet",
            croupierRemap: [SoundCatalog.voFlop.rawValue: SoundCatalog.voSkyFlop],
            fallbackKeys: [SoundCatalog.voSkyFlop.rawValue: "some.register.key"],
            ambient: .skypool, botVoices: .skypool)
        let (sound, fallback) = newCasino.croupier(SoundCatalog.voFlop)
        XCTAssertEqual(sound, SoundCatalog.voSkyFlop)
        XCTAssertEqual(fallback, "some.register.key")
        // An unknown casino id falls back to the identity (Riverwood) palette.
        XCTAssertEqual(CasinoAudio.of(casinoID: "does-not-exist").id, "riverwood")
        XCTAssertEqual(CasinoAudio.of(casinoID: "skypool").id, "skypool")
    }

    // MARK: - End-to-end: Skypool croupier (informative) → synthesis when mp3 missing

    func testSkypoolCroupierSpeaksItsRegisterFallbackThroughTheConductor() async {
        let audio = RecordingAudioService()
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = false
        var synths: [String] = []
        queue.synthesisObserver = { synths.append($0) }
        let conductor = SpeechConductor(audio: audio, queue: queue)

        // The Skypool flop voice isn't produced yet → its register fallback speaks.
        let (lead, fbKey) = CasinoAudio.skypool.croupier(SoundCatalog.voFlop)
        audio.missing = [lead!.rawValue]
        conductor.say(lead: lead, leadCategory: .croupier,
                      fallback: fbKey.map { uiLocalized($0) }, priority: .medium, reason: "flop")
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertTrue(audio.log.isEmpty, "the missing Skypool mp3 must not play")
        XCTAssertEqual(synths.count, 1, "the informative croupier line must fall back to synthesis (D-066/D-067)")
    }
}
