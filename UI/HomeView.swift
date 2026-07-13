// HomeView.swift
// =====================================================================
// The app's entry screen (D-035, generalised D-065): the game name, a tagline, and
// the list of CASINOS drawn from the registry (`Casinos.all`). Each casino is an
// enterable card; adding a casino is a data change, not a new card here. No
// "coming soon" placeholders — future casinos aren't anticipated (a later brick).
//
// Deliberately plain and typographic — SwiftUI only, no image assets yet. A classic
// serif face sets the app's tone (the individual casinos carry their own identity).

import SwiftUI
import GameWorld

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

                ForEach(Casinos.all) { casino in
                    casinoCard(casino)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func casinoCard(_ casino: Casino) -> some View {
        let theme = CasinoTheme.theme(for: casino)
        let blurb = uiLocalized(casino.blurbKey)
        return Button { app.openCasino(casino) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: casino.displayName)
                    .font(.system(.title2, design: theme.titleDesign).weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                Text(verbatim: blurb)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.panel.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.panelEdge.opacity(0.7), lineWidth: 1))
            )
        }
        .accessibilityIdentifier("home.casino.\(casino.id)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: uiLocalized("home.casino.a11y", casino.displayName, blurb)))
        .accessibilityHint(Text(verbatim: uiLocalized("home.casino.hint")))
    }
}
