// MachiavelliTableView.swift
// =====================================================================
// The playable Machiavelli table (D-072): a large, squared space of recombination, not
// a poker table. A thin TOP band holds two small opponent dots (no chips, no game data —
// just a name, a card count and a "thinking" mark). The CENTRE (≈2/3) is the shared
// TABLE of laid combinations; each card is an individually focusable element, and under
// each combination sits a table-edge KNOB — decoration for the sighted, but for a blind
// player a swipe-navigable element that announces the combination's title and offers
// CUSTOM ACTIONS to walk its cards. The BOTTOM third is the human's ordered hand.
//
// Two input modes over ONE engine predicate (D-072): the primary action "Piazza" opens
// the accessible composition box; the sighted player may instead DRAG a hand card onto a
// combination (or onto empty table space for a new one). Both mutate the same workspace;
// the turn's terminals (Pass / Draw) unlock on the SAME `MachiavelliRules` validity.

import SwiftUI
import GameEngine
import GameWorld
import Audio

struct MachiavelliTableScreen: View {
    @StateObject private var model: MachiavelliTableViewModel

    init(rules: MachiavelliTableRules, audio: AudioEngine, mode: AppVoiceOverMode,
         casinoAudio: CasinoAudio = .clockTower,
         returnLabel: String = uiLocalized("endgame.return"),
         progress: MachiavelliProgressStore = UserDefaultsMachiavelliProgress(),
         onLeave: @escaping (Int) -> Void) {
        let fastMode = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        _model = StateObject(wrappedValue: MachiavelliTableViewModel(
            fastMode: fastMode, audio: audio, mode: mode, rules: rules, casinoAudio: casinoAudio,
            progress: progress, returnLabel: returnLabel, onLeave: onLeave))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 6) {
                    leaveBar
                    MachiavelliOpponentBand(state: model.state, names: model.names)
                        .frame(height: geo.size.height * 0.10)
                    MachiavelliTableCentre(model: model)
                        .frame(maxHeight: .infinity)
                    MachiavelliActionBar(model: model)
                    MachiavelliHandZone(model: model)
                        .frame(height: geo.size.height * 0.28)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .accessibilityHidden(model.box != nil || model.outcome != nil)

                if let box = model.box {
                    ZStack {
                        Color.black.opacity(0.6).ignoresSafeArea().accessibilityHidden(true)
                        MachiavelliBoxView(model: model, box: box)
                    }
                }
                if let outcome = model.outcome {
                    EndOverlay(outcome: outcome, onReturn: { model.returnToCasino() }, returnLabel: model.returnLabel)
                }
            }
        }
        .task { await model.run() }
    }

    private var leaveBar: some View {
        HStack {
            Button { model.requestLeave() } label: {
                Label(uiLocalized("table.leave"), systemImage: "arrow.left.circle")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(TablePalette.primaryText)
                    .padding(.horizontal, 10).frame(height: 36)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
            }
            .disabled(model.pendingLeave)
            .accessibilityIdentifier("table.leave")
            .accessibilityHint(Text(uiLocalized("table.leave.hint")))
            Spacer()
            if model.pendingLeave {
                Text(verbatim: uiLocalized("table.leave.pending"))
                    .font(.caption).foregroundStyle(TablePalette.accent)
                    .accessibilityIdentifier("table.leave.pending")
            }
        }
    }
}

// MARK: - Top band: two small opponent dots

struct MachiavelliOpponentBand: View {
    let state: MachiavelliTableState
    let names: [Int: String]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(state.opponents, id: \.id) { seat in dot(seat) }
            Spacer()
            scoreTarget
        }
    }

    private func dot(_ seat: MachiavelliSeatPresentation) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(seat.isThinking ? TablePalette.accent : Color.white.opacity(0.25))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: names[seat.id] ?? "").font(.caption.weight(.semibold)).lineLimit(1)
                    .foregroundStyle(TablePalette.primaryText)
                Text(verbatim: uiLocalized("machiavelli.dot.cards", seat.handCount))
                    .font(.caption2.monospacedDigit()).foregroundStyle(TablePalette.secondaryText)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.3)))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("opponent.\(seat.id)")
        .accessibilityLabel(Text(verbatim: dotSummary(seat)))
    }

    private var scoreTarget: some View {
        Text(verbatim: uiLocalized("machiavelli.scoretarget", state.victoryThreshold))
            .font(.caption2.monospacedDigit()).foregroundStyle(TablePalette.secondaryText)
            .accessibilityIdentifier("machiavelli.scoretarget")
            .accessibilityLabel(Text(verbatim: uiLocalized("machiavelli.scoretarget.a11y", state.victoryThreshold)))
    }

    private func dotSummary(_ seat: MachiavelliSeatPresentation) -> String {
        var parts = [uiLocalized("machiavelli.dot.a11y", names[seat.id] ?? "", seat.handCount, seat.score)]
        if seat.isThinking { parts.append(uiLocalized("machiavelli.dot.thinking")) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Centre: the table of laid combinations, each with an edge knob

struct MachiavelliTableCentre: View {
    @ObservedObject var model: MachiavelliTableViewModel

    /// Editable groups (index + cards) during the human's turn, else the committed table.
    private var groups: [(groupIndex: Int?, cards: [Card])] {
        if let ws = model.workspace {
            return ws.tableEntries.enumerated().map { (groupIndex: $0.offset, cards: $0.element.map { $0.card }) }
        }
        return model.state.melds.map { (groupIndex: nil, cards: $0) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    MachiavelliMeldBlock(model: model, cards: group.cards, groupIndex: group.groupIndex)
                }
                if model.workspace != nil { newCombinationDropZone }
            }
            .padding(10)
            if groups.isEmpty && model.workspace == nil {
                Text(verbatim: uiLocalized("machiavelli.table.empty"))
                    .font(.subheadline).foregroundStyle(TablePalette.secondaryText)
                    .accessibilityIdentifier("machiavelli.table.empty")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TablePalette.felt.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(TablePalette.feltEdge.opacity(0.5), lineWidth: 2)))
        .accessibilityIdentifier("machiavelli.table")
    }

    /// A drop target for building a NEW combination by dragging (sighted path).
    private var newCombinationDropZone: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundStyle(TablePalette.accent.opacity(0.5))
            .frame(minHeight: 74)
            .overlay(Text(verbatim: uiLocalized("machiavelli.table.newcombo"))
                .font(.caption).foregroundStyle(TablePalette.secondaryText))
            .dropDestination(for: String.self) { items, _ in
                guard let idx = items.first.flatMap({ Int($0) }) else { return false }
                model.drop(cardIndex: idx, onGroup: nil); return true
            }
            .accessibilityHidden(true)   // sighted-only; the blind path is the box
    }
}

/// One laid combination: its cards (each focusable) plus the table-edge KNOB below.
struct MachiavelliMeldBlock: View {
    @ObservedObject var model: MachiavelliTableViewModel
    let cards: [Card]
    let groupIndex: Int?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    CardView(face: .up(card), size: .normal)
                }
            }
            knob
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.2)))
        .modifier(GroupDropModifier(model: model, groupIndex: groupIndex))
    }

    /// The table-edge knob: decoration for the sighted, an overview element for the blind
    /// (title + custom actions to walk the cards vertically — D-072).
    private var knob: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(TablePalette.accent.opacity(0.35))
            .frame(height: 5)
            .accessibilityElement()
            .accessibilityIdentifier(groupIndex.map { "machiavelli.knob.\($0)" } ?? "machiavelli.knob")
            .accessibilityLabel(Text(verbatim: MachiavelliSpeechMap.knobTitle(cards)))
            .accessibilityActions {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    Button(uiLocalized("machiavelli.knob.card", index + 1, CardText.spoken(card))) {
                        // Walk the combination's cards vertically: announce each on demand.
                        model.announce(CardText.spoken(card))
                    }
                }
            }
    }
}

/// Applies a drop destination to a meld block only during the human's turn (a group
/// index is present), leaving the read-only view untouched.
private struct GroupDropModifier: ViewModifier {
    @ObservedObject var model: MachiavelliTableViewModel
    let groupIndex: Int?
    func body(content: Content) -> some View {
        if let g = groupIndex {
            content.dropDestination(for: String.self) { items, _ in
                guard let idx = items.first.flatMap({ Int($0) }) else { return false }
                model.drop(cardIndex: idx, onGroup: g); return true
            }
        } else {
            content
        }
    }
}

// MARK: - Bottom: the human's hand (ordered, focusable, draggable)

struct MachiavelliHandZone: View {
    @ObservedObject var model: MachiavelliTableViewModel

    private var handEntries: [(index: Int?, card: Card)] {
        if let ws = model.workspace { return ws.handCards.map { (index: $0.index, card: $0.card) } }
        return (model.state.heroHand ?? []).map { (index: nil, card: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: uiLocalized("machiavelli.hand.header", handEntries.count))
                .font(.caption.weight(.semibold)).foregroundStyle(TablePalette.secondaryText)
                .accessibilityIdentifier("machiavelli.hand.header")
                .accessibilityLabel(Text(verbatim: uiLocalized("machiavelli.hand.header.a11y", handEntries.count)))
                .voiceOverFocusLanding()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 5)], alignment: .leading, spacing: 5) {
                    ForEach(Array(handEntries.enumerated()), id: \.offset) { _, entry in
                        handCard(entry)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.35))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(TablePalette.accent.opacity(0.5), lineWidth: 1)))
    }

    @ViewBuilder
    private func handCard(_ entry: (index: Int?, card: Card)) -> some View {
        let view = CardView(face: .up(entry.card), size: .normal)
        if let idx = entry.index {
            view.draggable(String(idx))    // sighted drag; the blind path is the box
                .accessibilityIdentifier("machiavelli.hand.card.\(idx)")
        } else {
            view
        }
    }
}

// MARK: - Action bar: Piazza · Passa · Pesca (human turn only)

struct MachiavelliActionBar: View {
    @ObservedObject var model: MachiavelliTableViewModel

    var body: some View {
        HStack(spacing: 10) {
            if model.workspace != nil {
                Button { model.openBox() } label: { label("machiavelli.action.piazza", primary: true) }
                    .accessibilityIdentifier("machiavelli.action.piazza")
                    .accessibilityHint(Text(uiLocalized("machiavelli.action.piazza.hint")))

                Button { model.passTurn() } label: {
                    label("machiavelli.action.pass", primary: false, enabled: model.workspace?.canPass == true)
                }
                .disabled(model.workspace?.canPass != true)
                .accessibilityIdentifier("machiavelli.action.pass")
                .accessibilityHint(Text(uiLocalized("machiavelli.action.pass.hint")))

                Button { model.drawTurn() } label: {
                    label("machiavelli.action.draw", primary: false, enabled: model.workspace?.mustDraw == true)
                }
                .disabled(model.workspace?.mustDraw != true)
                .accessibilityIdentifier("machiavelli.action.draw")
                .accessibilityHint(Text(uiLocalized("machiavelli.action.draw.hint")))
            } else {
                Text(verbatim: model.state.activeSeatID == nil ? "" : uiLocalized("machiavelli.waiting"))
                    .font(.caption).foregroundStyle(TablePalette.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("machiavelli.waiting")
            }
        }
        .frame(height: 52)
    }

    private func label(_ key: String, primary: Bool, enabled: Bool = true) -> some View {
        Text(verbatim: uiLocalized(key))
            .font(.headline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(primary ? .black : (enabled ? TablePalette.primaryText : TablePalette.foldedDim))
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(primary ? TablePalette.accent : Color.white.opacity(enabled ? 0.14 : 0.05)))
    }
}

#if DEBUG
#Preview { AppRootView() }
#endif
