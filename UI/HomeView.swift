// HomeView.swift
// =====================================================================
// The app's entry screen (D-035): the game name, a tagline, and the list of
// casinos. For now only the Riverwood is enterable; other casinos are visible but
// "coming soon" placeholders. Wrapped by GameChrome (settings + chips) at the root.
//
// Deliberately plain and typographic — SwiftUI only, no image assets yet (they
// arrive later). A classic serif face sets the tone.

import SwiftUI

struct HomeView: View {
    @ObservedObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: uiLocalized("app.title"))
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .foregroundStyle(TablePalette.primaryText)
                        .accessibilityIdentifier("home.title")
                        .accessibilityAddTraits(.isHeader)
                        .voiceOverFocusLanding()   // land VoiceOver here on entry (D-057)
                    Text(verbatim: uiLocalized("home.tagline"))
                        .font(.callout)
                        .foregroundStyle(TablePalette.secondaryText)
                }
                .padding(.top, 8)

                Text(verbatim: uiLocalized("home.casinos.header"))
                    .font(.headline)
                    .foregroundStyle(TablePalette.secondaryText)
                    .accessibilityAddTraits(.isHeader)

                casinoCard(name: "Riverwood Casinò", blurb: uiLocalized("home.riverwood.blurb"),
                           identifier: "home.casino.riverwood", available: true) {
                    app.openRiverwood()
                }
                comingSoon(name: "Velvet Palace", identifier: "home.casino.velvet")
                comingSoon(name: "Aurea Lounge", identifier: "home.casino.aurea")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func casinoCard(name: String, blurb: String, identifier: String,
                            available: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: name)
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(TablePalette.primaryText)
                Text(verbatim: blurb)
                    .font(.subheadline)
                    .foregroundStyle(TablePalette.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TablePalette.felt.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(TablePalette.accent.opacity(0.7), lineWidth: 1))
            )
        }
        .accessibilityIdentifier(identifier)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: uiLocalized("home.casino.a11y", name, blurb)))
        .accessibilityHint(Text(verbatim: uiLocalized("home.casino.hint")))
    }

    private func comingSoon(name: String, identifier: String) -> some View {
        HStack {
            Text(verbatim: name)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(TablePalette.secondaryText)
            Spacer()
            Text(verbatim: uiLocalized("world.comingSoon"))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .foregroundStyle(TablePalette.secondaryText)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .opacity(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(verbatim: uiLocalized("world.comingSoon.a11y", name)))
    }
}
