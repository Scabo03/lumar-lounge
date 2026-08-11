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
            // On-device pacing measurement (D-085): `-pacingBench` replaces the app
            // with a harness that times the real audio/spoken channel and prints its
            // numbers, so tuning rests on device timings rather than simulator ones.
            if PacingBench.isRequested {
                Color.black
                    .ignoresSafeArea()
                    .task { await PacingBench.run() }
            } else if DiagnosticsSelfTest.isRequested {
                // Collaudo of the diagnostic recorder (D-107): drive real sessions
                // with recording on and print back what was captured, so the harness
                // is proven BEFORE the app is handed over for the observed session.
                Color.black
                    .ignoresSafeArea()
                    .task { await DiagnosticsSelfTest.run() }
            } else {
            // M2.1: the app opens on Home, with navigation to the Riverwood Casino
            // and its tables (D-035). AppRootView owns the app-level state.
            AppRootView()
            }
        }
    }
}
