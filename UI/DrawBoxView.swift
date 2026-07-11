// DrawBoxView.swift
// =====================================================================
// The modal card-exchange box for the human's draw turn (D-044). A dedicated
// accessibility modal (D-027): the table behind is trapped, focus is pulled into
// the box on open. The five cards are shown large and are individually selectable
// with a tap; each selected card gets a DOUBLE visual signal — a bright brass
// border AND a dark X mark on its face — so a low-vision user catches at least one.
//
// Accessibility: every card is a VoiceOver button with an explicit label that
// includes its rank, suit and selection state; toggling announces the new state
// (via the queue's live value). A count element and an always-active Confirm
// button follow. No Cancel — deselecting all cards is equivalent (0 discards =
// stand pat). A rejected fifth selection is announced ("non puoi scartare più di
// quattro carte", posted by the model).

import SwiftUI
import GameEngine

struct DrawBoxView: View {
    @ObservedObject var model: DrawTableViewModel
    let box: DrawBoxState

    var body: some View {
        VStack(spacing: 16) {
            Text(verbatim: uiLocalized("draw.box.title"))
                .font(.headline).foregroundStyle(TablePalette.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(Text(verbatim: uiLocalized("draw.box.title.a11y", box.discardCount)))
                // Land VoiceOver on the title (which reads the instruction + count) when
                // the box opens (D-044, via the shared focus-landing pattern D-057).
                .voiceOverFocusLanding()

            HStack(spacing: 8) {
                ForEach(Array(box.cards.enumerated()), id: \.offset) { index, card in
                    cardButton(card, index: index)
                }
            }

            Text(verbatim: countText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TablePalette.accent)
                .accessibilityIdentifier("draw.box.count")
                .accessibilityLabel(Text(verbatim: countText))

            Button { model.confirmDraw() } label: {
                Text(verbatim: confirmTitle)
                    .font(.headline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.black)
                    .background(RoundedRectangle(cornerRadius: 12).fill(TablePalette.accent))
            }
            .accessibilityIdentifier("draw.confirm")
            .accessibilityLabel(Text(verbatim: confirmLabel))
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.10, green: 0.09, blue: 0.07))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(TablePalette.accent, lineWidth: 2)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawbox")
    }

    private func cardButton(_ card: Card, index: Int) -> some View {
        let selected = box.isSelected(card)
        return Button { model.toggleDrawCard(card) } label: {
            ZStack {
                CardView(face: .up(card), size: .huge)
                // Dark mark on the face (second selection signal, for low vision).
                // ALWAYS present — toggled by opacity, never added/removed — so the
                // button's accessibility subtree stays structurally stable across a
                // selection and VoiceOver keeps a single, un-shifting element (D-046).
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.42))
                    .opacity(selected ? 1 : 0)
                Image(systemName: "xmark")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)
                    .opacity(selected ? 1 : 0)
            }
            // Bright brass border (first selection signal).
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? TablePalette.accent : Color.clear, lineWidth: 4)
            )
            // Collapse the card face's own a11y element: the button is ONE leaf whose
            // label we supply, so selecting only updates the label — it never restructures
            // the subtree nor moves the focus (D-046).
            .accessibilityElement(children: .ignore)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("draw.card.\(index)")
        .accessibilityLabel(Text(verbatim: cardLabel(card, selected: selected)))
    }

    private func cardLabel(_ card: Card, selected: Bool) -> String {
        let name = CardText.spoken(card)
        return selected
            ? uiLocalized("draw.card.a11y.selected", name)
            : uiLocalized("draw.card.a11y.unselected", name)
    }

    private var countText: String {
        box.discardCount == 0
            ? uiLocalized("draw.box.count.zero")
            : uiLocalized("draw.box.count.n", box.discardCount)
    }
    private var confirmTitle: String {
        box.discardCount == 0 ? uiLocalized("draw.confirm.standpat") : uiLocalized("draw.confirm.n", box.discardCount)
    }
    private var confirmLabel: String {
        box.discardCount == 0
            ? uiLocalized("draw.confirm.standpat.a11y")
            : uiLocalized("draw.confirm.n.a11y", box.discardCount)
    }
}
