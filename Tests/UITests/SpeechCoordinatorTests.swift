import XCTest
@testable import UI

/// The pure audio ⇄ VoiceOver timing rule (D-028): VoiceOver waits out a spoken
/// croupier/bot cue (plus a small gap) before speaking, and adds no latency when
/// nothing spoken is playing.
final class SpeechCoordinatorTests: XCTestCase {

    func testNoDelayWhenNothingSpokenIsPlaying() {
        XCTAssertEqual(SpeechCoordinator.voiceOverDelay(spokenRemaining: 0), 0)
    }

    func testWaitsForTheSpokenCuePlusAGap() {
        XCTAssertEqual(SpeechCoordinator.voiceOverDelay(spokenRemaining: 1.0),
                       1.0 + SpeechCoordinator.gap, accuracy: 0.0001)
    }

    func testNegativeRemainingIsTreatedAsNothingPlaying() {
        XCTAssertEqual(SpeechCoordinator.voiceOverDelay(spokenRemaining: -0.5), 0)
    }
}
