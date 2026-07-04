// PokerTableView.swift
// =====================================================================
// The first PLAYABLE screen (M1.7): a layered Hold'em table where the human is
// the protagonist at the bottom and the bots are abstracted badges at the top.
//
//   ┌───────────────────────────────┐
//   │  opponents (badges)           │  top band
//   ├───────────────────────────────┤
//   │  table: board · pot · button  │  centre
//   ├───────────────────────────────┤
//   │  Check/Call   Fold   Raise     │  action bar
//   ├───────────────────────────────┤
//   │  🂡 🂮   your cards + stack     │  bottom band (hero)
//   └───────────────────────────────┘
//
// A pure listener + input forwarder: it renders `TableViewModel.state` and sends
// the human's taps to the model, which forwards them to GameWorld's
// HumanActionProvider. No game logic here. Accessibility is first-class (D-016).

import SwiftUI
import GameEngine

public struct PokerTableView: View {
    /// Bumping this restarts the whole session (fresh view + view model).
    @State private var restartToken = 0

    public init() {}

    public var body: some View {
        TableScreen(seed: 20_260_704 &+ UInt64(restartToken),
                    fastMode: ProcessInfo.processInfo.arguments.contains("-uiTesting"),
                    onRestart: { restartToken += 1 })
            .id(restartToken)
    }
}

struct TableScreen: View {
    @StateObject private var model: TableViewModel
    let onRestart: () -> Void

    init(seed: UInt64, fastMode: Bool, onRestart: @escaping () -> Void) {
        _model = StateObject(wrappedValue: TableViewModel(seed: seed, fastMode: fastMode))
        self.onRestart = onRestart
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TablePalette.background.ignoresSafeArea()

                VStack(spacing: 6) {
                    OpponentBadgesView(state: model.state, names: model.names)
                        .frame(height: geometry.size.height * 0.20)

                    TableCenterView(state: model.state, names: model.names)
                        .frame(maxHeight: .infinity)

                    ActionBarView(model: model)

                    HeroZoneView(state: model.state)
                        .frame(height: geometry.size.height * 0.28)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if let box = model.raiseBox {
                    ZStack {
                        Color.black.opacity(0.45).ignoresSafeArea()
                            .onTapGesture { model.cancelRaise() }
                            .accessibilityHidden(true)
                        RaiseBoxView(model: model, box: box)
                    }
                }

                if let outcome = model.outcome {
                    EndOverlay(outcome: outcome, onRestart: onRestart)
                }
            }
        }
        .task { await model.run() }
    }
}

// MARK: - Centre: the table itself (community cards, pot, button)

struct TableCenterView: View {
    let state: TableState
    let names: [Int: String]

    var body: some View {
        ZStack {
            Ellipse()
                .fill(TablePalette.felt)
                .overlay(Ellipse().strokeBorder(TablePalette.feltEdge, lineWidth: 3))
                .accessibilityElement()
                .accessibilityIdentifier("table.container")
                .accessibilityLabel(Text(verbatim: uiLocalized("table.a11y")))

            VStack(spacing: 10) {
                buttonIndicator
                board
                pot
            }
            .padding(.horizontal, 12)
        }
    }

    private var buttonIndicator: some View {
        Text(verbatim: buttonText)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(TablePalette.accent)
            .accessibilityIdentifier("table.button")
            .accessibilityLabel(Text(verbatim: buttonA11y))
    }

    private var board: some View {
        HStack(spacing: 6) {
            if state.board.isEmpty {
                Text(verbatim: uiLocalized("board.empty"))
                    .font(.subheadline)
                    .foregroundStyle(TablePalette.secondaryText)
            } else {
                ForEach(Array(state.board.enumerated()), id: \.offset) { _, card in
                    CardView(face: .up(card))
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("table.board")
        .accessibilityLabel(Text(verbatim: boardA11y))
    }

    private var pot: some View {
        Text(verbatim: uiLocalized("pot.label", state.pot))
            .font(.headline.monospacedDigit())
            .foregroundStyle(TablePalette.primaryText)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.4)))
            .overlay(Capsule().strokeBorder(TablePalette.accent.opacity(0.7), lineWidth: 1))
            .accessibilityIdentifier("table.pot")
            .accessibilityLabel(Text(verbatim: uiLocalized("pot.a11y", state.pot)))
    }

    private var buttonText: String {
        guard let id = state.buttonSeatID, let name = names[id] else { return uiLocalized("button.none") }
        return uiLocalized("button.holder", name)
    }
    private var buttonA11y: String {
        guard let id = state.buttonSeatID, let name = names[id] else { return uiLocalized("button.none") }
        return uiLocalized("button.a11y", name)
    }
    private var boardA11y: String {
        state.board.isEmpty ? uiLocalized("board.a11y.empty") : uiLocalized("board.a11y", CardText.spoken(state.board))
    }
}

#if DEBUG
#Preview {
    PokerTableView()
}
#endif
