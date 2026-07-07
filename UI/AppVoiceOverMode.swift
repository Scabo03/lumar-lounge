// AppVoiceOverMode.swift
// =====================================================================
// The app's OWN VoiceOver mode (D-034): an observable, persisted on/off state,
// independent of iOS system VoiceOver. When ON, the UI paces the visual timeline
// to the spoken channel (eye and ear advance together); when OFF, the UI keeps its
// fast internal human rhythm. The user may keep it ON with iOS VoiceOver off, or
// OFF with iOS VoiceOver on — the two are deliberately independent.
//
// Default: OFF, regardless of iOS. Persisted in UserDefaults (a simple preference),
// restored at launch; the store is injectable for tests.

import Foundation

@MainActor
public final class AppVoiceOverMode: ObservableObject {

    @Published public var isEnabled: Bool {
        didSet { store.set(isEnabled, forKey: Self.key) }
    }

    private let store: UserDefaults
    private static let key = "lumar.app.voiceOverMode"

    public init(store: UserDefaults = .standard) {
        self.store = store
        // Initial assignment does not trigger `didSet`, so loading never re-persists.
        self.isEnabled = store.object(forKey: Self.key) as? Bool ?? false
    }
}
