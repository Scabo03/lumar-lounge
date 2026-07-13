import XCTest
@testable import UI
import Audio

/// The cabling of the real Skypool mp3s (D-068). Verifies that every slot we cabled
/// points to a file that actually exists in `Resources/Audio/` (so a forgotten or
/// mis-renamed file fails loudly, not silently), that the still-empty slots keep their
/// graceful fallback, and that the newly-audible bot COLOUR stays on the ambient
/// channel — never enqueued as a game announcement, and no D-051 double now that the
/// croupier files exist.
@MainActor
final class SkypoolAudioCablingTests: XCTestCase {

    private func audioDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Audio")
    }
    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: audioDir().appendingPathComponent("\(name).mp3").path)
    }

    // MARK: - Cabled slots must resolve to a real file (catches a bad rename)

    /// The Skypool mp3s produced and cabled in this pass. If a rename is wrong, the
    /// file won't be at the expected path and this fails — no silent miss (D-068).
    private let cabled: [SoundID] = [
        // Croupier (informative)
        SoundCatalog.voSkyBlindSmall, SoundCatalog.voSkyBlindBig, SoundCatalog.voSkyRoleButton,
        SoundCatalog.voSkyYourTurn, SoundCatalog.voSkyFlop, SoundCatalog.voSkyTurn,
        SoundCatalog.voSkyRiver, SoundCatalog.voSkyShowdown, SoundCatalog.voSkyActionAllIn,
        SoundCatalog.voSkyPotAwarded, SoundCatalog.voSkySplitPot, SoundCatalog.voSkyStakesUp,
        // Ambient
        SoundCatalog.ambSkypoolCalm1, SoundCatalog.ambSkypoolCalm2,
        SoundCatalog.ambSkypoolTense, SoundCatalog.ambSkypoolWater,
        // Bot colour (ambient)
        SoundCatalog.vobSkyNoviceExcited, SoundCatalog.vobSkyNoviceDisappointed,
        SoundCatalog.vobSkyNoviceNervous, SoundCatalog.vobSkyRockGrunt,
        SoundCatalog.vobSkyAggressorConfident, SoundCatalog.vobSkyAggressorTaunt,
        SoundCatalog.vobSkyAggressorBluffGiveaway,   // renamed from the Downloads 'aggressor_nervous'
    ]

    func testEveryCabledSlotHasItsFileOnDisk() {
        for id in cabled {
            XCTAssertTrue(exists(id.rawValue),
                          "cabled Skypool slot '\(id.rawValue)' has no mp3 in Resources/Audio — forgotten or mis-renamed?")
        }
    }

    /// The slots NOT produced yet stay empty and lean on their fallback (croupier →
    /// synthesis, bot colour → silence). Documenting them here means adding one later
    /// is a deliberate change to this list.
    func testKnownStillEmptySlots() {
        XCTAssertFalse(exists(SoundCatalog.voSkyHandStart.rawValue),
                       "hand-start chime not produced → silent (add here when it lands)")
        XCTAssertFalse(exists(SoundCatalog.voSkyPotLimit.rawValue),
                       "pot-limit reminder is reserved/unused → not produced")
    }

    // MARK: - Bot COLOUR is on the ambient channel, not the announcement queue (D-068)

    func testBotColourPlaysAsAudioAndIsNeverEnqueuedAsAnAnnouncement() async {
        let audio = RecordingAudioService()     // nothing missing → the vob plays
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = false
        var synths: [String] = []
        queue.synthesisObserver = { synths.append($0) }
        let conductor = SpeechConductor(audio: audio, queue: queue)

        // A bot colour line with no attribution synthesis: pure ambient colour.
        conductor.say(lead: SoundCatalog.vobSkyRockGrunt, leadCategory: .botVoice,
                      synthesis: nil, priority: .medium)
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(audio.botVoicePlays, [SoundCatalog.vobSkyRockGrunt],
                       "the bot colour must play as .botVoice AUDIO")
        XCTAssertTrue(synths.isEmpty, "bot colour must NEVER be enqueued as an announcement (it is ambient, not info)")
    }

    // MARK: - No D-051 double now that the croupier mp3 exists

    func testPresentCroupierMp3PlaysAndItsRegisterFallbackStaysSilent() async {
        let audio = RecordingAudioService()     // voSkyFlop present (nothing missing)
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = false
        var synths: [String] = []
        queue.synthesisObserver = { synths.append($0) }
        let conductor = SpeechConductor(audio: audio, queue: queue)

        // The Skypool flop: mp3 present + a content synthesis + the register fallback.
        conductor.say(lead: SoundCatalog.voSkyFlop, leadCategory: .croupier,
                      synthesis: "flop-cards", fallback: "register-flop", priority: .medium)
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(audio.croupierPlays, [SoundCatalog.voSkyFlop], "the present mp3 plays")
        XCTAssertEqual(synths, ["flop-cards"],
                       "only the content synthesis speaks; the register fallback must NOT double it (D-051)")
    }
}
