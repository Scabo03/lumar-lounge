import XCTest

/// Every main screen and every modal/overlay must land VoiceOver focus on its first
/// element when it appears (D-057), so focus is never stranded on the previous
/// screen after a transition. VoiceOver focus itself can't be asserted in a unit
/// test, so this guards the declaration: each screen source must apply the shared
/// `.voiceOverFocusLanding()` pattern at least once.
final class FocusLandingTests: XCTestCase {

    func testEveryScreenAndModalDeclaresAFocusLanding() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // source file → the screen/modal it hosts.
        let hosts = [
            "UI/HomeView.swift": "Home",
            "UI/RiverwoodView.swift": "Riverwood",
            "UI/GameChrome.swift": "Settings",
            "UI/HeroZoneView.swift": "Texas table (hero)",
            "UI/DrawTableView.swift": "Draw table (hero)",
            "UI/ActionBarView.swift": "Raise box + end-of-game overlay",
            "UI/DrawBoxView.swift": "Draw exchange box",
        ]
        for (rel, what) in hosts {
            let src = try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            XCTAssertTrue(src.contains("voiceOverFocusLanding()"),
                          "\(what) (\(rel)) must land VoiceOver focus on its first element (D-057)")
        }
    }
}
