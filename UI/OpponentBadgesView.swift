// OpponentBadgesView.swift
// =====================================================================
// The top band: the bots, abstracted as badges (name, chip stack, status). No
// face-down cards on the table — realistically the opponents hold them in hand
// — so opponents are just badges here (D-022). Each badge is one accessibility
// element with a spoken, Italian-phonetic summary.

import SwiftUI
import GameEngine

struct OpponentBadgesView: View {
    let state: TableState
    let names: [Int: String]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(state.opponents, id: \.id) { seat in
                badge(for: seat)
            }
        }
        .frame(maxWidth: .infinity)
        // No identifier on this container: it would collapse the badges beneath
        // into one element (D-019). The badges (opponent.N) are the leaves.
    }

    private func badge(for seat: SeatPresentation) -> some View {
        let isActive = state.activeSeatID == seat.id
        return VStack(spacing: 3) {
            Text(verbatim: names[seat.id] ?? "")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(seat.isBusted ? TablePalette.foldedDim : TablePalette.primaryText)
            Text(verbatim: uiLocalized("seat.chips", seat.chips))
                .font(.caption.monospacedDigit())
                .foregroundStyle(TablePalette.secondaryText)
            statusLine(seat)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(isActive ? 0.5 : 0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isActive ? TablePalette.accent : Color.white.opacity(0.12),
                                      lineWidth: isActive ? 2.5 : 1)
                )
        )
        .opacity(seat.isFolded && !seat.isBusted ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilitySummary(seat, isActive: isActive)))
        .accessibilityIdentifier("opponent.\(seat.id)")
    }

    @ViewBuilder
    private func statusLine(_ seat: SeatPresentation) -> some View {
        HStack(spacing: 4) {
            if seat.isButton { pill(uiLocalized("badge.button"), TablePalette.accent, .black) }
            if state.smallBlindSeatID == seat.id { pill(uiLocalized("badge.smallBlind"), .white.opacity(0.9), .black) }
            if state.bigBlindSeatID == seat.id { pill(uiLocalized("badge.bigBlind"), .white.opacity(0.9), .black) }
            if seat.isBusted { pill(uiLocalized("badge.busted"), TablePalette.foldedDim, .black) }
            else if seat.isAllIn { pill(uiLocalized("badge.allIn"), TablePalette.redSuit, .white) }
            else if seat.isFolded { pill(uiLocalized("badge.folded"), Color.white.opacity(0.25), .white) }
        }
        .accessibilityHidden(true)
    }

    private func pill(_ text: String, _ background: Color, _ foreground: Color) -> some View {
        Text(verbatim: text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(background))
            .foregroundStyle(foreground)
    }

    private func accessibilitySummary(_ seat: SeatPresentation, isActive: Bool) -> String {
        var parts = [uiLocalized("seat.a11y.base", names[seat.id] ?? "", seat.chips)]
        if isActive { parts.append(uiLocalized("seat.a11y.acting")) }
        if seat.isButton { parts.append(uiLocalized("seat.a11y.button")) }
        if state.smallBlindSeatID == seat.id { parts.append(uiLocalized("seat.a11y.smallBlind")) }
        if state.bigBlindSeatID == seat.id { parts.append(uiLocalized("seat.a11y.bigBlind")) }
        if seat.isBusted { parts.append(uiLocalized("seat.a11y.busted")) }
        else if seat.isAllIn { parts.append(uiLocalized("seat.a11y.allIn")) }
        else if seat.isFolded { parts.append(uiLocalized("seat.a11y.folded")) }
        return parts.joined(separator: ", ")
    }
}
