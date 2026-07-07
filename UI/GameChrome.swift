// GameChrome.swift
// =====================================================================
// The persistent app chrome (D-033): a reusable shell around any main screen that
// hosts a top bar with a permanent Settings button (top-right) and presents the
// Settings screen. Introduced now, above the table, so every future screen (menu,
// casino, sign-in) inherits the same button without re-implementing it.
//
// The top bar reserves its own strip, so the button never overlaps the screen's
// content (e.g. the opponents' badges). Fully accessible: the button reads
// "Impostazioni" with a hint, and the sheet is navigable top-to-bottom.

import SwiftUI

public struct GameChrome<Content: View>: View {
    @ObservedObject var voMode: AppVoiceOverMode
    @State private var showingSettings = false
    private let content: Content

    public init(voMode: AppVoiceOverMode, @ViewBuilder content: () -> Content) {
        self.voMode = voMode
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: .top) {
            TablePalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                content
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(voMode: voMode)
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(TablePalette.primaryText)
                    .frame(width: 44, height: 44)              // comfortable tap target
                    .background(
                        Circle().fill(Color.white.opacity(0.12))
                            .overlay(Circle().strokeBorder(TablePalette.accent.opacity(0.8), lineWidth: 1))
                    )
            }
            .accessibilityIdentifier("settings.button")
            .accessibilityLabel(Text(uiLocalized("settings.button.a11y")))
            .accessibilityHint(Text(uiLocalized("settings.button.hint")))
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}

// MARK: - Settings screen (reusable; grows with future options)

struct SettingsView: View {
    @ObservedObject var voMode: AppVoiceOverMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(uiLocalized("settings.vomode.label"), isOn: $voMode.isEnabled)
                        .accessibilityIdentifier("settings.vomode.switch")
                        .accessibilityLabel(Text(uiLocalized("settings.vomode.a11y")))
                        .accessibilityHint(Text(uiLocalized("settings.vomode.hint")))
                } footer: {
                    // The description and the iOS-independence note (D-034).
                    Text(uiLocalized("settings.vomode.desc") + "\n\n" + uiLocalized("settings.vomode.footer"))
                }
            }
            .navigationTitle(Text(uiLocalized("settings.title")))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(uiLocalized("settings.done")) { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
    }
}
