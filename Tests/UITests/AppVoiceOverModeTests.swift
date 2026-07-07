import XCTest
@testable import UI

/// The app's own VoiceOver mode (D-034): default OFF, persisted, restored at launch.
@MainActor
final class AppVoiceOverModeTests: XCTestCase {

    private func freshStore() -> UserDefaults {
        let name = "AppVoiceOverModeTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    func testDefaultsToOffWhenNothingSaved() {
        let mode = AppVoiceOverMode(store: freshStore())
        XCTAssertFalse(mode.isEnabled)
    }

    func testTogglingPersistsAndIsRestoredAtNextLaunch() {
        let store = freshStore()
        let mode = AppVoiceOverMode(store: store)
        mode.isEnabled = true
        // A new instance (a new launch) restores the saved value.
        let relaunched = AppVoiceOverMode(store: store)
        XCTAssertTrue(relaunched.isEnabled)
    }

    func testTurningBackOffIsAlsoPersisted() {
        let store = freshStore()
        let mode = AppVoiceOverMode(store: store)
        mode.isEnabled = true
        mode.isEnabled = false
        XCTAssertFalse(AppVoiceOverMode(store: store).isEnabled)
    }

    func testIndependentInstancesShareThePersistedValue() {
        let store = freshStore()
        AppVoiceOverMode(store: store).isEnabled = true
        XCTAssertTrue(AppVoiceOverMode(store: store).isEnabled)
    }
}
