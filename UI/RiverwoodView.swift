// RiverwoodView.swift
// =====================================================================
// The Riverwood Casino screen (D-035): a rustic, frontier-America card room. Lists
// the tables you can sit at. For M2.1: Texas Hold'em Classic, Texas Hold'em Fast,
// and a not-yet-playable Five-Card Draw slot. A row is enterable only if the player
// can cover the buy-in; otherwise it's visible but disabled and VoiceOver says so.
//
// SwiftUI + serif typography only — no wood textures yet (they arrive later).

import SwiftUI
import GameWorld

struct RiverwoodView: View {
    @ObservedObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "Riverwood Casinò")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(TablePalette.primaryText)
                        .accessibilityIdentifier("riverwood.title")
                        .accessibilityAddTraits(.isHeader)
                        .voiceOverFocusLanding()   // land VoiceOver here on entry (D-057)
                    Text(verbatim: uiLocalized("riverwood.tagline"))
                        .font(.callout).italic()
                        .foregroundStyle(TablePalette.secondaryText)
                }
                .padding(.top, 8)

                Text(verbatim: uiLocalized("riverwood.tables.header"))
                    .font(.headline).foregroundStyle(TablePalette.secondaryText)
                    .accessibilityAddTraits(.isHeader)

                tableRow(style: .classic, title: uiLocalized("table.holdem.title"),
                         styleName: uiLocalized("table.style.classic"),
                         buyIn: TableRules.classic.buyIn, freeSeats: 1, identifier: "riverwood.table.classic")

                tableRow(style: .fast, title: uiLocalized("table.holdem.title"),
                         styleName: uiLocalized("table.style.fast"),
                         buyIn: TableRules.fast.buyIn, freeSeats: 1, identifier: "riverwood.table.fast")

                drawTableRow(title: uiLocalized("table.draw.title"),
                             styleName: uiLocalized("table.draw.room"),
                             buyIn: DrawTableRules.riverwoodWhiskey.buyIn, freeSeats: 1,
                             identifier: "riverwood.table.draw")
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tableRow(style: TableFormat, title: String, styleName: String,
                          buyIn: Int, freeSeats: Int, identifier: String) -> some View {
        let affordable = app.canAfford(buyIn)
        return Button {
            if affordable { app.sitDown(style, buyIn: buyIn) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(title) — \(styleName)")
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(affordable ? TablePalette.primaryText : TablePalette.foldedDim)
                    Text(verbatim: uiLocalized("table.row.info", buyIn, freeSeats))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(TablePalette.secondaryText)
                }
                Spacer()
                Image(systemName: affordable ? "chevron.right" : "lock.fill")
                    .foregroundStyle(affordable ? TablePalette.accent : TablePalette.foldedDim)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TablePalette.felt.opacity(affordable ? 0.55 : 0.28))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(TablePalette.accent.opacity(affordable ? 0.7 : 0.25), lineWidth: 1))
            )
        }
        .disabled(!affordable)
        .accessibilityIdentifier(identifier)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: affordable
            ? uiLocalized("table.row.a11y", title, styleName, buyIn, freeSeats)
            : uiLocalized("table.row.a11y.locked", title, styleName, buyIn)))
    }

    /// The Five-Card Draw table row (D-044): enterable when the player can cover the
    /// 2000-gettoni buy-in, otherwise visible-but-locked like the Texas rows.
    private func drawTableRow(title: String, styleName: String, buyIn: Int,
                              freeSeats: Int, identifier: String) -> some View {
        let affordable = app.canAfford(buyIn)
        return Button {
            if affordable { app.sitDownDraw(buyIn: buyIn) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(title) — \(styleName)")
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(affordable ? TablePalette.primaryText : TablePalette.foldedDim)
                    Text(verbatim: uiLocalized("table.row.info", buyIn, freeSeats))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(TablePalette.secondaryText)
                }
                Spacer()
                Image(systemName: affordable ? "chevron.right" : "lock.fill")
                    .foregroundStyle(affordable ? TablePalette.accent : TablePalette.foldedDim)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TablePalette.felt.opacity(affordable ? 0.55 : 0.28))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(TablePalette.accent.opacity(affordable ? 0.7 : 0.25), lineWidth: 1)))
        }
        .disabled(!affordable)
        .accessibilityIdentifier(identifier)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: affordable
            ? uiLocalized("table.row.a11y", title, styleName, buyIn, freeSeats)
            : uiLocalized("table.row.a11y.locked", title, styleName, buyIn)))
    }

}
