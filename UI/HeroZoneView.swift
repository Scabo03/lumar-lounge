// HeroZoneView.swift
// =====================================================================
// The bottom band: the human player is the protagonist. Two large, face-up
// hole cards next to the current chip stack. No redundant badge — this zone IS
// the human's representation (D-022). Cards stay visible for the whole hand,
// until muck (fold) or showdown.

import SwiftUI
import GameEngine

struct HeroZoneView: View {
    let state: TableState

    private var heroSeat: SeatPresentation? {
        state.heroSeatID.flatMap { id in state.seats.first { $0.id == id } }
    }

    var body: some View {
        HStack(spacing: 16) {
            cards
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: uiLocalized("hero.you"))
                    .font(.headline)
                    .foregroundStyle(TablePalette.primaryText)
                Text(verbatim: uiLocalized("seat.chips", heroSeat?.chips ?? 0))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(TablePalette.accent)
                    .accessibilityLabel(Text(verbatim: uiLocalized("hero.stack.a11y", heroSeat?.chips ?? 0)))
                    .voiceOverFocusLanding()   // land VoiceOver on the hero on table entry (D-057)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(TablePalette.accent.opacity(0.6), lineWidth: 1.5))
        )
        // No accessibility modifier on this container: its children (the cards
        // leaf and the stack) stay individually accessible (D-019).
    }

    @ViewBuilder
    private var cards: some View {
        if let hole = state.heroHole, hole.count == 2 {
            HStack(spacing: 8) {
                CardView(face: .up(hole[0]), big: true)
                CardView(face: .up(hole[1]), big: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("hero.cards")
            .accessibilityLabel(Text(verbatim: uiLocalized("hero.cards.a11y", CardText.spoken(hole))))
        } else {
            // No cards (between hands, or mucked after a fold).
            Text(verbatim: uiLocalized("hero.nocards"))
                .font(.subheadline)
                .foregroundStyle(TablePalette.secondaryText)
                .frame(minHeight: 108)
                .accessibilityIdentifier("hero.cards")
                .accessibilityLabel(Text(verbatim: uiLocalized("hero.nocards.a11y")))
        }
    }
}
