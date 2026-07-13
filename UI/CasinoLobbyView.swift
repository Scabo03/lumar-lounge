// CasinoLobbyView.swift
// =====================================================================
// The generic casino lobby (D-065): ONE screen that renders any `Casino` and lists
// its tables. It replaced the hardcoded RiverwoodView when the Skypool arrived, so a
// new casino is a data change (a `Casino` in the registry) rather than a copied
// screen. Themed per casino (D-066): the Riverwood is warm serif on green, the
// Skypool cool sans on slate.
//
// A row is enterable only if the player can cover the buy-in — the sole economic
// barrier (D-065); otherwise it is visible but disabled and VoiceOver says so. Table
// ids double as accessibility identifiers, preserving the Riverwood's existing ones.

import SwiftUI
import GameWorld

struct CasinoLobbyView: View {
    let casino: Casino
    @ObservedObject var app: AppState

    private var theme: CasinoTheme { CasinoTheme.theme(for: casino) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: casino.displayName)
                        .font(.system(size: 34, weight: .bold, design: theme.titleDesign))
                        .foregroundStyle(theme.primaryText)
                        .accessibilityIdentifier("\(casino.id).title")
                        .accessibilityAddTraits(.isHeader)
                        // Visible name stays English; VoiceOver reads the ear-verified
                        // spoken name (D-060) — this is also the focus-landing element.
                        .accessibilityLabel(Text(verbatim: casino.spokenNameKey.map(uiLocalized) ?? casino.displayName))
                        .voiceOverFocusLanding()   // land VoiceOver here on entry (D-057)
                    Text(verbatim: uiLocalized(casino.taglineKey))
                        .font(.callout).italic()
                        .foregroundStyle(theme.secondaryText)
                }
                .padding(.top, 8)

                Text(verbatim: uiLocalized("riverwood.tables.header"))
                    .font(.headline).foregroundStyle(theme.secondaryText)
                    .accessibilityAddTraits(.isHeader)

                ForEach(casino.tables) { table in
                    tableRow(table)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tableRow(_ table: CasinoTable) -> some View {
        let title = uiLocalized(table.titleKey)
        let styleName = uiLocalized(table.subtitleKey)
        let buyIn = table.buyIn
        let freeSeats = 1
        let affordable = app.canAfford(buyIn)
        return Button {
            if affordable { app.sitDown(table) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(title) — \(styleName)")
                        .font(.system(.title3, design: theme.titleDesign).weight(.semibold))
                        .foregroundStyle(affordable ? theme.primaryText : TablePalette.foldedDim)
                    Text(verbatim: uiLocalized("table.row.info", buyIn, freeSeats))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                Image(systemName: affordable ? "chevron.right" : "lock.fill")
                    .foregroundStyle(affordable ? theme.accent : TablePalette.foldedDim)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.panel.opacity(affordable ? 0.55 : 0.28))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.panelEdge.opacity(affordable ? 0.7 : 0.25), lineWidth: 1))
            )
        }
        .disabled(!affordable)
        .accessibilityIdentifier(table.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: affordable
            ? uiLocalized("table.row.a11y", title, styleName, buyIn, freeSeats)
            : uiLocalized("table.row.a11y.locked", title, styleName, buyIn)))
    }
}
