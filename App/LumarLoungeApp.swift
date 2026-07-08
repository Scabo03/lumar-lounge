// App shell
// =====================================================================
// The thin Xcode app target. Its only job is to own the bundle (identifier,
// Info.plist, asset catalog, localization tables) and to present the UI
// module's root view. All real screens live in the UI module.

import SwiftUI
import UI

@main
struct LumarLoungeApp: App {
    var body: some Scene {
        WindowGroup {
            // M2.1: the app opens on Home, with navigation to the Riverwood Casino
            // and its tables (D-035). AppRootView owns the app-level state.
            AppRootView()
        }
    }
}
