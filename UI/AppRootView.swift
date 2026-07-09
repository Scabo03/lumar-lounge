// AppRootView.swift
// =====================================================================
// The application root (D-035): owns the app-level state (navigation + wallet) and
// the app-wide VoiceOver mode, wraps each screen in the persistent GameChrome, and
// drives the per-screen ambient. This is the new entry point — the app no longer
// opens straight onto a poker table.
//
// One shared AudioEngine spans all screens (single audio session, ambient
// continuity). Home/Riverwood ambients fall back to a lounge bed until the
// dedicated files are produced (D-035). Navigation plays a (silent-for-now)
// transition blip.

import SwiftUI
import GameWorld
import Audio

public struct AppRootView: View {
    @StateObject private var app: AppState
    @StateObject private var voMode = AppVoiceOverMode()
    private let audio: AudioEngine

    public init() {
        self.audio = AudioEngine()
        // UI tests launch with -resetWallet for a deterministic fresh balance.
        let store: ChipsStore = ProcessInfo.processInfo.arguments.contains("-resetWallet")
            ? InMemoryChipsStore() : UserDefaultsChipsStore()
        _app = StateObject(wrappedValue: AppState(account: PlayerAccount(store: store)))
    }

    public var body: some View {
        content
            .animation(.easeInOut(duration: 0.25), value: app.screen)
            .onAppear { applyAmbient() }
            .onChange(of: app.screen) { _ in
                audio.play(SoundCatalog.uiNavigation, category: .ui)   // silent until produced
                applyAmbient()
            }
    }

    @ViewBuilder private var content: some View {
        switch app.screen {
        case .home:
            GameChrome(voMode: voMode, chips: app.chips) {
                HomeView(app: app)
            }
        case .riverwood:
            GameChrome(voMode: voMode, chips: app.chips, leading: backToHome) {
                RiverwoodView(app: app)
            }
        case let .table(style):
            GameChrome(voMode: voMode) {
                TableScreen(rules: rules(for: style), audio: audio, mode: voMode,
                            onLeave: { remaining in app.leaveTable(cashingOut: remaining) })
                    .id(style)   // a fresh session per sit-down
            }
        case .drawTable:
            GameChrome(voMode: voMode) {
                DrawTableScreen(rules: .riverwoodWhiskey, audio: audio, mode: voMode,
                                onLeave: { remaining in app.leaveTable(cashingOut: remaining) })
            }
        }
    }

    private var backToHome: ChromeAction {
        ChromeAction(label: uiLocalized("chrome.back"), systemImage: "chevron.left",
                     identifier: "chrome.back") { app.goHome() }
    }

    private func rules(for style: TableFormat) -> TableRules {
        style == .fast ? .fast : .classic
    }

    // MARK: - Ambient per screen (D-035)

    private func applyAmbient() {
        switch app.screen {
        case .home:
            audio.crossfadeAmbient(to: bed(SoundCatalog.ambHomeNeutral, SoundCatalog.ambLoungeCalm1), duration: 1.0)
            audio.setAmbientScale(0.6, duration: 1.0)   // discreet, we're outside the casinos
        case .riverwood:
            audio.crossfadeAmbient(to: bed(SoundCatalog.ambRiverwoodCalm1, SoundCatalog.ambLoungeCalm2), duration: 1.0)
            audio.setAmbientScale(1.0, duration: 1.0)
        case .table, .drawTable:
            // The table's AudioDirector takes over the ambient on sessionBegan.
            break
        }
    }

    /// The preferred bed if its file exists, else a lounge fallback (D-035).
    private func bed(_ preferred: SoundID, _ fallback: SoundID) -> SoundID {
        audio.isAvailable(preferred) ? preferred : fallback
    }
}
