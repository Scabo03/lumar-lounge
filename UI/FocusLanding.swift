// FocusLanding.swift
// =====================================================================
// The reusable VoiceOver focus-landing pattern (D-057). When a screen or modal
// appears, VoiceOver's focus must not be left stranded on an element of the screen
// that just went away (the user swipes and hits the end-of-list "tonk" because
// nothing is focused). Every main screen (Home, Riverwood, the tables, Settings)
// and every modal/overlay (Raise box, Draw box, end-of-game overlay) declares its
// FIRST focus element and lands VoiceOver on it when it appears.
//
// The mechanism, all declarative:
//  • post `.screenChanged` so VoiceOver re-scans the new content (guarded for the
//    macOS `swift test` host, where UIKit is absent);
//  • move focus onto THIS element via `@AccessibilityFocusState`, deferred one
//    runloop so the element exists in the tree first (the same timing D-027 uses).
//
// `.screenChanged` fires before any queued content announcements (the queue is a
// separate channel), so the two don't fight: the new screen is scanned, focus
// lands, then any contextual announcements follow.
//
// Apply `.voiceOverFocusLanding()` to the element that should receive focus.

import SwiftUI

struct VoiceOverFocusLanding: ViewModifier {
    @AccessibilityFocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityFocused($focused)
            .onAppear {
                // Ask VoiceOver to re-scan the new screen. Routed through the queue,
                // the single point that posts to VoiceOver (D-032/D-057).
                AnnouncementQueue.postScreenChanged()
                // Defer one runloop so the element is in the accessibility tree.
                DispatchQueue.main.async { focused = true }
            }
    }
}

extension View {
    /// Lands VoiceOver focus on this element when it appears, and asks VoiceOver to
    /// re-scan the screen (D-057). Put it on the first meaningful element of every
    /// screen and modal so focus is never stranded after a transition.
    func voiceOverFocusLanding() -> some View { modifier(VoiceOverFocusLanding()) }
}
