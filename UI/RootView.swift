// UI
// =====================================================================
// All SwiftUI views of the application live in this module.
//
// RULE: may import GameWorld, GameEngine and Audio. Nothing imports UI
// except the thin app shell. The dependency direction is
// UI → GameWorld → GameEngine, plus UI → Audio.
//
// Every view sets its accessibility identifiers and labels up front (even
// when minimal), and every user-visible string comes from the localization
// tables — never a hard-coded literal.

import SwiftUI
import GameWorld
import Audio

/// The application's minimal root screen.
public struct RootView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            LocalizedStrings.appTitle
                .font(.largeTitle.weight(.bold))
                .accessibilityIdentifier("root.title")
                .accessibilityLabel(LocalizedStrings.appTitle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("root.container")
        .accessibilityElement(children: .contain)
    }
}

/// Centralised access to localized, user-visible strings used by the UI layer.
/// Strings are resolved from the main bundle's localization tables, so no
/// user-facing text is ever written inline in a view.
enum LocalizedStrings {
    static var appTitle: Text {
        Text("app.title", bundle: .main, comment: "Main brand title shown on the root screen")
    }
}

#if DEBUG
#Preview {
    RootView()
}
#endif
