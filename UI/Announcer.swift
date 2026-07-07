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

    /// Whether VoiceOver is currently active (always false without UIKit).
    public var isVoiceOverRunning: Bool {
        #if canImport(UIKit)
        return UIAccessibility.isVoiceOverRunning
        #else
        return false
        #endif
    }

    /// Announces a message via VoiceOver (no-op if VoiceOver isn't running, or
    /// on platforms without UIKit).
    ///
    /// - Parameters:
    ///   - interrupting: when `true`, the announcement is posted at high priority
    ///     so it interrupts a pending one — used for the rapid +/- of the Raise
    ///     box, where only the latest value matters (D-020).
    ///   - after: seconds to wait before posting, so VoiceOver doesn't talk over a
    ///     croupier/bot voice still playing (D-028). 0 means post immediately.
    @MainActor
    public func announce(_ message: String, interrupting: Bool = false, after delay: TimeInterval = 0) {
        #if canImport(UIKit)
        guard UIAccessibility.isVoiceOverRunning else { return }
        // Interrupting posts also get a small beat so a tap activation clears first
        // (D-027); otherwise honour the caller's coordination delay verbatim.
        let wait = interrupting ? max(delay, 0.1) : delay
        let argument: Any
        if interrupting {
            var attributed = AttributedString(message)
            attributed.accessibilitySpeechAnnouncementPriority = .high
            // IMPORTANT: `.announcement` expects an NSAttributedString. A raw Swift
            // AttributedString is silently dropped (D-027) — bridge it so the .high
            // priority survives and a burst of +/- taps collapses to the last value.
            argument = NSAttributedString(attributed)
        } else {
            argument = message
        }
        if wait > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                UIAccessibility.post(notification: .announcement, argument: argument)
            }
        } else {
            UIAccessibility.post(notification: .announcement, argument: argument)
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
