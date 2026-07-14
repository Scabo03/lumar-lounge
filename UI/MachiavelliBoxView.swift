// MachiavelliBoxView.swift
// =====================================================================
// The modal COMPOSITION box ("Piazza", D-072/D-074), divided into two halves. LOWER
// HALF: a single HORIZONTAL RIBBON — a pure linear sequence, the most legible structure
// for a player who navigates by swipe (the gesture is linear, so the structure is too:
// no translation between the two). It runs: the ordered HAND cards → a vertical "tavolo"
// divider → then each laid COMBINATION preceded by its own TITLED divider (the same
// title as the table-edge knob, e.g. "scala di picche dal cinque al dieci"). Scrolling
// the ribbon, the player meets a title, then that combination's cards, then the next
// title, and so on — the table's structure ARRIVES while scrolling instead of having to
// be rebuilt from memory. (A grid of rows that enter and leave the view — the earlier
// design — was caotic for exactly this reason: D-074.) UPPER HALF: the POOL of selected
// cards.
//
// THE IMPOSED ACOUSTIC DISTINCTION (D-072, non-negotiable): ribbon cards (lower) carry NO
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
// SUBTREE STABILITY (D-046/D-052/D-074): the ribbon's structure is FIXED for the box's
// life (selecting only changes the pool, never the table), a ribbon card's label is
// CONSTANT (just the card), and its selection highlight is toggled by opacity — so a
// selection never restructures the subtree and VoiceOver never re-lands. Crucial with a
// ribbon where the player makes dozens of consecutive selections.

import SwiftUI
import GameEngine

struct MachiavelliBoxView: View {
    @ObservedObject var model: MachiavelliTableViewModel
    let box: MachiavelliBoxState

    private let columns = [GridItem(.adaptive(minimum: 46), spacing: 6)]
    private let ribbonCardHeight: CGFloat = 74   // == CardView .medium height

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
            ribbonHalf
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

    // MARK: - Lower half: the HORIZONTAL RIBBON (hand · "tavolo" · titled combinations)

    private var ribbonHalf: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: uiLocalized("machiavelli.box.chain"))
                .font(.subheadline.weight(.semibold)).foregroundStyle(TablePalette.secondaryText)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 6) {
                    // 1. Hand cards.
                    ForEach(box.handCards) { ribbonCard($0) }
                    // 2. The "tavolo" divider.
                    tavoloDivider
                    // 3. Each laid combination: its titled divider, then its cards.
                    ForEach(Array(box.tableGroups.enumerated()), id: \.offset) { groupIndex, group in
                        HStack(spacing: 6) {
                            combinationDivider(group.map { $0.card }, index: groupIndex)
                            ForEach(group) { ribbonCard($0) }
                        }
                    }
                }
                .padding(.vertical, 4).padding(.horizontal, 2)
            }
            .frame(height: ribbonCardHeight + 16)
        }
    }

    /// The vertical "tavolo" divider — an accessibility element the blind player hears
    /// between the hand cards and the laid combinations; a thin bar for the sighted.
    private var tavoloDivider: some View {
        verticalDivider
            .accessibilityElement()
            .accessibilityIdentifier("machiavelli.box.divider")
            .accessibilityLabel(Text(uiLocalized("machiavelli.box.tabledivider.a11y")))
    }

    /// A combination's titled divider — preceding its cards in the ribbon; announces the
    /// SAME title as the table-edge knob (D-074), e.g. "scala di picche dal cinque al dieci".
    private func combinationDivider(_ cards: [Card], index: Int) -> some View {
        verticalDivider
            .accessibilityElement()
            .accessibilityIdentifier("machiavelli.box.combodivider.\(index)")
            .accessibilityLabel(Text(verbatim: MachiavelliSpeechMap.knobTitle(cards)))
    }

    private var verticalDivider: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(TablePalette.accent.opacity(0.55))
            .frame(width: 3, height: ribbonCardHeight)
    }

    private func ribbonCard(_ entry: MachiavelliChainCard) -> some View {
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
