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
    ///
    /// - Parameter interrupting: when `true`, the announcement is posted at high
    ///   priority so it interrupts a pending one — used for the rapid +/- of the
    ///   Raise box, where only the latest value matters (D-020).
    @MainActor
    public func announce(_ message: String, interrupting: Bool = false) {
        #if canImport(UIKit)
        guard UIAccessibility.isVoiceOverRunning else { return }
        if interrupting {
            var announcement = AttributedString(message)
            announcement.accessibilitySpeechAnnouncementPriority = .high
            UIAccessibility.post(notification: .announcement, argument: announcement)
        } else {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
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
