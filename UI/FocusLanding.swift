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

    /// Claims VoiceOver focus for this element whenever `claim` is true (D-092).
    ///
    /// This is the RETURN path that `voiceOverFocusLanding()` cannot cover. That one
    /// is `onAppear`-driven, which is right for a screen or a modal being presented,
    /// but a modal DISMISSAL is a different shape: the table underneath was never
    /// removed from the tree — it was only `accessibilityHidden` — so nothing appears
    /// and nothing re-fires, while the button the player just pressed has ceased to
    /// exist with the cursor still on it. The blind player is then stranded on
    /// nothing and must hunt for the table by hand.
    ///
    /// So this modifier lands focus on BOTH shapes: the element is newly inserted
    /// while already claiming, or it was there all along and the claim flips false →
    /// true. It posts `.layoutChanged`, not `.screenChanged`, because the screen did
    /// not change — only part of it did.
    func voiceOverFocusClaim(_ claim: Bool) -> some View {
        modifier(VoiceOverFocusClaim(claim: claim))
    }

    /// The edge-triggered form of `voiceOverFocusClaim(_:)`, for a destination that was
    /// on screen all along (D-092). The poker tables never remove the hero zone, so
    /// there is no appearance to hook; instead the view model bumps a token when a box
    /// closes, and focus comes home on the change — and ONLY on the change, so table
    /// entry is left to `voiceOverFocusLanding()` and the two never fight.
    func voiceOverFocusClaim<T: Equatable>(onChangeOf token: T) -> some View {
        modifier(VoiceOverFocusToken(token: token))
    }
}

/// See `voiceOverFocusClaim(onChangeOf:)`.
struct VoiceOverFocusToken<T: Equatable>: ViewModifier {
    let token: T
    @AccessibilityFocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityFocused($focused)
            .onChange(of: token) { _ in
                AnnouncementQueue.postLayoutChanged()
                DispatchQueue.main.async { focused = true }
            }
    }
}

/// See `voiceOverFocusClaim(_:)`.
struct VoiceOverFocusClaim: ViewModifier {
    let claim: Bool
    @AccessibilityFocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityFocused($focused)
            .onAppear { if claim { land() } }
            .onChange(of: claim) { now in if now { land() } }
    }

    private func land() {
        AnnouncementQueue.postLayoutChanged()
        // Deferred one runloop so the element is in the tree first (D-027 timing).
        DispatchQueue.main.async { focused = true }
    }
}
