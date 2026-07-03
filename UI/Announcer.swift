// Announcer.swift
// =====================================================================
// Posts VoiceOver announcements. On iOS this uses `UIAccessibility`, which is
// exactly what dynamic announcements are for. Guarded by `#if canImport(UIKit)`
// so the UI module still compiles on the macOS host (needed by `swift test`);
// there it is simply a no-op (D-016).

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Speaks messages through VoiceOver, when it is running.
public struct Announcer: Sendable {

    public init() {}

    /// Announces a message via VoiceOver (no-op if VoiceOver isn't running, or
    /// on platforms without UIKit).
    @MainActor
    public func announce(_ message: String) {
        #if canImport(UIKit)
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }

    /// Signals that the screen's layout changed substantially.
    @MainActor
    public func screenChanged() {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        #endif
    }
}
