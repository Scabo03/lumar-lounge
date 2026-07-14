// MachiavelliBoxView.swift
// =====================================================================
// The modal COMPOSITION box ("Piazza", D-072) — much larger than the poker Raise box,
// divided into two halves. LOWER HALF: a swipe-scrollable CHAIN — the player's hand
// cards, a divider announced as "tavolo", then every card already laid on the table.
// The player selects freely from it, own cards or anyone's laid cards. UPPER HALF: the
// POOL of what is selected so far.
//
// THE IMPOSED ACOUSTIC DISTINCTION (D-072, non-negotiable): chain cards (lower) carry NO
// state in their VoiceOver label; every pool card (upper) announces itself as SELECTED.
// So after dozens of swipes a blind player always knows WHICH ZONE they are in without
// having to remember. The sighted player gets the same from on-screen position — parity,
// not help.
//
// The top states the SELECTION STATE (count + what it currently is) — DESCRIBING, never
// ADVISING (D-072). Confirm unlocks exactly when the selected set is a legal combination
// per the engine (`viewModel.boxCanConfirm`). The pool is hypothetical: the table is
// untouched until Confirm, and deselecting is always free.
//
// SUBTREE STABILITY (D-046/D-052): a chain card's label is CONSTANT (just the card) and
// its selection highlight is toggled by opacity, never by inserting/removing subviews —
// so selecting never restructures the subtree and VoiceOver never re-lands. The pool is
// a separate section; growing it doesn't touch any chain element.

import SwiftUI
import GameEngine

struct MachiavelliBoxView: View {
    @ObservedObject var model: MachiavelliTableViewModel
    let box: MachiavelliBoxState

    private let columns = [GridItem(.adaptive(minimum: 46), spacing: 6)]

    var body: some View {
        VStack(spacing: 14) {
            // Selection-state read-out (focus lands here). DESCRIBES, never advises.
            Text(verbatim: MachiavelliSpeechMap.describeSelection(box.selectedCards))
                .font(.headline).foregroundStyle(TablePalette.primaryText)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("machiavelli.box.state")
                .voiceOverFocusLanding()

            poolHalf
            Divider().overlay(TablePalette.accent.opacity(0.5))
            chainHalf
            buttons
        }
        .padding(18)
        .frame(maxWidth: 560, maxHeight: 640)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.12, green: 0.10, blue: 0.07))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(TablePalette.accent, lineWidth: 2)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("machiavellibox")
    }

    // MARK: - Upper half: the pool (every card announces "selected")

    private var poolHalf: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: uiLocalized("machiavelli.box.pool"))
                .font(.subheadline.weight(.semibold)).foregroundStyle(TablePalette.accent)
                .accessibilityAddTraits(.isHeader)
            if box.selected.isEmpty {
                Text(verbatim: uiLocalized("machiavelli.box.pool.empty"))
                    .font(.footnote).foregroundStyle(TablePalette.secondaryText)
                    .accessibilityIdentifier("machiavelli.pool.empty")
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(box.poolEntries) { entry in poolCard(entry) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 96, alignment: .top)
    }

    private func poolCard(_ entry: MachiavelliChainCard) -> some View {
        Button { model.toggleBoxCard(entry.index) } label: {
            CardView(face: .up(entry.card), size: .medium)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(TablePalette.accent, lineWidth: 3))
                .accessibilityElement(children: .ignore)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("machiavelli.pool.card.\(entry.index)")
        // The pool card ALWAYS announces "selected" — the zone marker (D-072).
        .accessibilityLabel(Text(verbatim: uiLocalized("machiavelli.card.a11y.selected", CardText.spoken(entry.card))))
        .accessibilityHint(Text(uiLocalized("machiavelli.pool.card.hint")))
    }

    // MARK: - Lower half: the chain (hand · "tavolo" · table). NO state in labels.

    private var chainHalf: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: uiLocalized("machiavelli.box.chain"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(TablePalette.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(box.chain.filter { $0.isHand }) { chainCard($0) }
                }
                dividerElement
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(box.chain.filter { !$0.isHand }) { chainCard($0) }
                }
            }
        }
        .frame(maxHeight: 300)
    }

    /// The "tavolo" divider — an accessibility element the blind player hears between the
    /// hand cards and the laid cards; decoration for the sighted.
    private var dividerElement: some View {
        HStack(spacing: 8) {
            Rectangle().fill(TablePalette.accent.opacity(0.4)).frame(height: 1)
            Text(verbatim: uiLocalized("machiavelli.box.tabledivider"))
                .font(.caption.weight(.bold)).foregroundStyle(TablePalette.secondaryText)
            Rectangle().fill(TablePalette.accent.opacity(0.4)).frame(height: 1)
        }
        .accessibilityElement()
        .accessibilityIdentifier("machiavelli.box.divider")
        .accessibilityLabel(Text(uiLocalized("machiavelli.box.tabledivider.a11y")))
    }

    private func chainCard(_ entry: MachiavelliChainCard) -> some View {
        let selected = box.isSelected(entry.index)
        return Button { model.toggleBoxCard(entry.index) } label: {
            ZStack {
                CardView(face: .up(entry.card), size: .medium)
                // Selection highlight for the SIGHTED — opacity-toggled, always present,
                // so the subtree never changes structure on selection (D-046/D-052).
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(TablePalette.accent, lineWidth: 3)
                    .opacity(selected ? 1 : 0)
            }
            .accessibilityElement(children: .ignore)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("machiavelli.chain.card.\(entry.index)")
        // CONSTANT label — NO selection state (the chain-zone marker, D-072). The state
        // lives in the pool half; this keeps the subtree and focus stable across taps.
        .accessibilityLabel(Text(verbatim: CardText.spoken(entry.card)))
        .accessibilityHint(Text(uiLocalized("machiavelli.chain.card.hint")))
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack(spacing: 10) {
            Button { model.closeBox() } label: {
                Text(verbatim: uiLocalized("machiavelli.box.close"))
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(TablePalette.primaryText)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
            }
            .accessibilityIdentifier("machiavelli.box.close")

            Button { model.restartTurn() } label: {
                Text(verbatim: uiLocalized("machiavelli.box.restart"))
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(TablePalette.primaryText)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
            }
            .accessibilityIdentifier("machiavelli.box.restart")
            .accessibilityHint(Text(uiLocalized("machiavelli.box.restart.hint")))

            Button { model.confirmBox() } label: {
                Text(verbatim: uiLocalized("machiavelli.box.confirm"))
                    .font(.headline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(.black)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(model.boxCanConfirm ? TablePalette.accent : TablePalette.foldedDim))
            }
            .disabled(!model.boxCanConfirm)
            .accessibilityIdentifier("machiavelli.box.confirm")
            .accessibilityLabel(Text(uiLocalized("machiavelli.box.confirm.a11y")))
        }
    }
}
