// SeatView.swift
// =====================================================================
// One seat around the table: its cards (face-down, or revealed at showdown),
// name, current chip stack, and role/status badges (button, blinds, folded,
// all-in, busted).
//
// The whole seat is a single accessibility element with a spoken, Italian-
// phonetic summary, so VoiceOver reads it as one coherent unit and a blind user
// gets exactly what a sighted user sees (D-016).

import SwiftUI
import GameEngine

struct SeatView: View {
    let seat: SeatPresentation
    let name: String
    let isSmallBlind: Bool
    let isBigBlind: Bool

    var body: some View {
        VStack(spacing: 4) {
            cards
            Text(verbatim: name)
                .font(.headline)
                .foregroundStyle(seat.isBusted ? TablePalette.foldedDim : TablePalette.primaryText)
            Text(verbatim: uiLocalized("seat.chips", seat.chips))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(TablePalette.secondaryText)
            badges
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(seat.isFolded || seat.isBusted ? 0.15 : 0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(seat.isButton ? TablePalette.accent : Color.white.opacity(0.15),
                                      lineWidth: seat.isButton ? 2 : 1)
                )
        )
        .opacity(seat.isFolded && !seat.isBusted ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilitySummary))
        .accessibilityIdentifier("seat.\(seat.id)")
    }

    private var cards: some View {
        HStack(spacing: 3) {
            if let revealed = seat.revealedHole {
                ForEach(Array(revealed.enumerated()), id: \.offset) { _, card in
                    CardView(face: .up(card))
                }
            } else if seat.hasCards && !seat.isFolded {
                CardView(face: .down)
                CardView(face: .down)
            } else {
                // Keep the vertical space stable when there are no cards.
                Color.clear.frame(height: 1)
            }
        }
    }

    private var badges: some View {
        HStack(spacing: 4) {
            if seat.isButton { badge(uiLocalized("badge.button"), TablePalette.accent, Color.black) }
            if isSmallBlind { badge(uiLocalized("badge.smallBlind"), Color.white.opacity(0.9), Color.black) }
            if isBigBlind { badge(uiLocalized("badge.bigBlind"), Color.white.opacity(0.9), Color.black) }
            if seat.isAllIn { badge(uiLocalized("badge.allIn"), TablePalette.redSuit, Color.white) }
            if seat.isBusted { badge(uiLocalized("badge.busted"), TablePalette.foldedDim, Color.black) }
        }
        .accessibilityHidden(true) // conveyed in the seat's spoken summary
    }

    private func badge(_ text: String, _ background: Color, _ foreground: Color) -> some View {
        Text(verbatim: text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(background))
            .foregroundStyle(foreground)
    }

    /// A concise, Italian-phonetic spoken description of the seat.
    private var accessibilitySummary: String {
        var parts = [uiLocalized("seat.a11y.base", name, seat.chips)]
        if seat.isButton { parts.append(uiLocalized("seat.a11y.button")) }
        if isSmallBlind { parts.append(uiLocalized("seat.a11y.smallBlind")) }
        if isBigBlind { parts.append(uiLocalized("seat.a11y.bigBlind")) }
        if let revealed = seat.revealedHole { parts.append(uiLocalized("seat.a11y.shows", CardText.spoken(revealed))) }
        else if seat.hasCards && !seat.isFolded { parts.append(uiLocalized("seat.a11y.holding")) }
        if seat.isAllIn { parts.append(uiLocalized("seat.a11y.allIn")) }
        if seat.isFolded && !seat.isBusted { parts.append(uiLocalized("seat.a11y.folded")) }
        if seat.isBusted { parts.append(uiLocalized("seat.a11y.busted")) }
        return parts.joined(separator: ", ")
    }
}
