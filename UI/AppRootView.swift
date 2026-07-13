// AppRootView.swift
// =====================================================================
// The application root (D-035, generalised D-065): owns the app-level state
// (navigation + wallet) and the app-wide VoiceOver mode, wraps each screen in the
// persistent GameChrome, and drives the per-screen ambient. Navigation is now
// casino-agnostic — Home, a `Casino` lobby, or a `CasinoTable` — and the table screen
// is built from the table's game (Texas / Draw / Omaha).
//
// One shared AudioEngine spans all screens (single audio session, ambient
// continuity). Home/casino ambients fall back to a lounge bed until the dedicated
// files are produced. Navigation plays a (silent-for-now) transition blip.

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
        case let .casino(casino):
            let theme = CasinoTheme.theme(for: casino)
            GameChrome(voMode: voMode, chips: app.chips, leading: backToHome, background: theme.background) {
                CasinoLobbyView(casino: casino, app: app)
            }
        case let .table(table):
            let theme = CasinoTheme.theme(forTable: table.id)
            GameChrome(voMode: voMode, background: theme.background) {
                tableScreen(table)
                    .id(table.id)   // a fresh session per sit-down
            }
        }
    }

    /// Builds the right game screen for a table, with its casino's return label.
    @ViewBuilder private func tableScreen(_ table: CasinoTable) -> some View {
        let returnLabel = uiLocalized(Casinos.casino(hosting: table.id)?.returnLabelKey ?? "endgame.return")
        // The hosting casino's audio palette — its croupier, register and ambient are an
        // attribute of the CASINO, not the game, so all its tables share one voice (D-067).
        let palette = CasinoAudio.hosting(table: table.id)
        let onLeave: (Int) -> Void = { remaining in app.leaveTable(cashingOut: remaining) }
        switch table.game {
        case let .texas(rules):
            TableScreen(rules: rules, audio: audio, mode: voMode, returnLabel: returnLabel,
                        casinoAudio: palette, onLeave: onLeave)
        case let .draw(rules):
            DrawTableScreen(rules: rules, audio: audio, mode: voMode, returnLabel: returnLabel, onLeave: onLeave)
        case let .omaha(rules):
            OmahaTableScreen(rules: rules, audio: audio, mode: voMode, returnLabel: returnLabel,
                             casinoAudio: palette, onLeave: onLeave)
        }
    }

    private var backToHome: ChromeAction {
        ChromeAction(label: uiLocalized("chrome.back"), systemImage: "chevron.left",
                     identifier: "chrome.back") { app.goHome() }
    }

    // MARK: - Ambient per screen (D-035/D-066)

    private func applyAmbient() {
        switch app.screen {
        case .home:
            audio.crossfadeAmbient(to: bed(SoundCatalog.ambHomeNeutral, SoundCatalog.ambLoungeCalm1), duration: 1.0)
            audio.setAmbientScale(0.6, duration: 1.0)   // discreet, we're outside the casinos
        case let .casino(casino):
            audio.crossfadeAmbient(to: casinoBed(casino), duration: 1.0)
            audio.setAmbientScale(1.0, duration: 1.0)
        case .table:
            // The table's audio director takes over the ambient on sessionBegan.
            break
        }
    }

    /// A casino lobby's calm bed, falling back to a lounge bed until the dedicated file
    /// is produced (D-035/D-066). The Skypool gets its cool urban bed.
    private func casinoBed(_ casino: Casino) -> SoundID {
        switch casino.id {
        case "skypool": return bed(SoundCatalog.ambSkypoolCalm1, SoundCatalog.ambLoungeCalm2)
        default:        return bed(SoundCatalog.ambRiverwoodCalm1, SoundCatalog.ambLoungeCalm2)
        }
    }

    /// The preferred bed if its file exists, else a lounge fallback (D-035).
    private func bed(_ preferred: SoundID, _ fallback: SoundID) -> SoundID {
        audio.isAvailable(preferred) ? preferred : fallback
    }
}
