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
            // The single screen of M1.6: the demo poker table. (No navigation
            // yet — that arrives with later bricks.)
            PokerTableView()
        }
    }
}
