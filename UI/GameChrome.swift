// GameChrome.swift
// =====================================================================
// The persistent app chrome (D-033/D-035): a reusable shell around any main screen
// with a top bar (an optional LEADING action — back / leave table — on the left, a
// permanent Settings button on the right), an optional CHIPS balance row, and the
// Settings sheet. Every screen (Home, Riverwood, Table) is wrapped in it, so the
// settings button and wallet are consistent everywhere.

import SwiftUI
import GameWorld

/// A labelled action for the chrome's leading slot (back, leave table, …).
public struct ChromeAction {
    let label: String
    let systemImage: String
    let identifier: String
    let action: () -> Void
    public init(label: String, systemImage: String, identifier: String, action: @escaping () -> Void) {
        self.label = label; self.systemImage = systemImage; self.identifier = identifier; self.action = action
    }
}

public struct GameChrome<Content: View>: View {
    @ObservedObject var voMode: AppVoiceOverMode
    /// The chips balance to show under the bar (nil at the table, where fiches show).
    let chips: Int?
    let leading: ChromeAction?
    @State private var showingSettings = false
    private let content: Content

    public init(voMode: AppVoiceOverMode, chips: Int? = nil, leading: ChromeAction? = nil,
                @ViewBuilder content: () -> Content) {
        self.voMode = voMode
        self.chips = chips
        self.leading = leading
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: .top) {
            TablePalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if let chips { chipsBar(chips) }
                content
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView(voMode: voMode) }
    }

    private var topBar: some View {
        HStack {
            if let leading {
                Button(action: leading.action) {
                    Label(leading.label, systemImage: leading.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TablePalette.primaryText)
                        .padding(.horizontal, 10).frame(height: 44)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .accessibilityIdentifier(leading.identifier)
            } else {
                Spacer().frame(width: 1)
            }
            Spacer()
            // ⚠️ TEMPORANEO (D-050): visible badge whenever free-play test mode is on.
            if DebugFlags.freePlay { freePlayBadge }
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(TablePalette.primaryText)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.12))
                        .overlay(Circle().strokeBorder(TablePalette.accent.opacity(0.8), lineWidth: 1)))
            }
            .accessibilityIdentifier("settings.button")
            .accessibilityLabel(Text(uiLocalized("settings.button.a11y")))
            .accessibilityHint(Text(uiLocalized("settings.button.hint")))
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    /// ⚠️ TEMPORANEO (D-050): the free-play indicator. Non-invasive, high-contrast,
    /// and VoiceOver-announceable ("Modalità test gioco libero attiva").
    private var freePlayBadge: some View {
        Text(verbatim: uiLocalized("debug.freeplay.badge"))
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.orange))
            .foregroundStyle(.black)
            .accessibilityElement()
            .accessibilityIdentifier("debug.freeplay.badge")
            .accessibilityLabel(Text(uiLocalized("debug.freeplay.a11y")))
    }

    private func chipsBar(_ chips: Int) -> some View {
        HStack {
            Text(verbatim: uiLocalized("chrome.chips", chips))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(TablePalette.accent)
                .accessibilityIdentifier("chrome.chips")
                .accessibilityLabel(Text(verbatim: uiLocalized("chrome.chips.a11y", chips)))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
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
