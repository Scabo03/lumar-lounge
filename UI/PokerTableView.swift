// PokerTableView.swift
// =====================================================================
// The first real screen: a minimalist, high-contrast Texas Hold'em table that
// listens to the SessionDriver's public event stream (M1.5) and shows a demo
// session between three bots unfolding, at a human pace, fully narrated to
// VoiceOver.
//
// It is a pure LISTENER: no game logic lives here (that would belong in
// GameWorld). It renders `TableViewModel.state` and lets the view model drive
// the rhythm. Accessibility is first-class on every element (D-016, D-019).

import SwiftUI
import GameEngine

public struct PokerTableView: View {
    @StateObject private var model = TableViewModel()

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                TablePalette.background.ignoresSafeArea()

                feltShape(in: geometry.size)

                centerArea
                    .frame(maxWidth: geometry.size.width * 0.5)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                ForEach(model.state.seats, id: \.id) { seat in
                    SeatView(seat: seat,
                             name: model.names[seat.id] ?? "",
                             isSmallBlind: model.state.smallBlindSeatID == seat.id,
                             isBigBlind: model.state.bigBlindSeatID == seat.id)
                        .position(seatPosition(for: seat, in: geometry.size))
                }

                if model.state.phase == .finished { winnerBanner }
            }
        }
        .background(TablePalette.background.ignoresSafeArea())
        .task {
            // Under UI testing the demo is left static (pre-populated) so the
            // accessibility tree is stable to inspect; otherwise it auto-plays.
            if !ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                await model.run()
            }
        }
        // NOTE: no accessibility modifier on this container — doing so would
        // collapse the whole subtree into one element and hide the seats. The
        // "table.container" element is the felt (below); children stay exposed.
    }

    // MARK: - Table felt

    private func feltShape(in size: CGSize) -> some View {
        Ellipse()
            .fill(TablePalette.felt)
            .overlay(Ellipse().strokeBorder(TablePalette.feltEdge, lineWidth: 3))
            .frame(width: size.width * 0.82, height: size.height * 0.66)
            .position(x: size.width / 2, y: size.height / 2)
            .accessibilityElement()
            .accessibilityIdentifier("table.container")
            .accessibilityLabel(Text(verbatim: uiLocalized("table.a11y")))
    }

    // MARK: - Centre: button holder, board, pot

    private var centerArea: some View {
        VStack(spacing: 12) {
            buttonIndicator
            boardView
            potView
        }
    }

    private var buttonIndicator: some View {
        Text(verbatim: buttonText)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(TablePalette.accent)
            .accessibilityIdentifier("table.button")
            .accessibilityLabel(Text(verbatim: buttonAccessibility))
    }

    private var boardView: some View {
        HStack(spacing: 6) {
            if model.state.board.isEmpty {
                Text(verbatim: uiLocalized("board.empty"))
                    .font(.subheadline)
                    .foregroundStyle(TablePalette.secondaryText)
            } else {
                ForEach(Array(model.state.board.enumerated()), id: \.offset) { _, card in
                    CardView(face: .up(card))
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("table.board")
        .accessibilityLabel(Text(verbatim: boardAccessibility))
    }

    private var potView: some View {
        Text(verbatim: uiLocalized("pot.label", model.state.pot))
            .font(.headline.monospacedDigit())
            .foregroundStyle(TablePalette.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.4)))
            .overlay(Capsule().strokeBorder(TablePalette.accent.opacity(0.7), lineWidth: 1))
            .accessibilityIdentifier("table.pot")
            .accessibilityLabel(Text(verbatim: uiLocalized("pot.a11y", model.state.pot)))
    }

    // MARK: - Winner

    private var winnerBanner: some View {
        let winnerName = model.state.winnerSeatID.flatMap { model.names[$0] } ?? ""
        return Text(verbatim: uiLocalized("winner.banner", winnerName))
            .font(.title2.weight(.bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(TablePalette.primaryText)
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 16).fill(TablePalette.cardBack))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(TablePalette.accent, lineWidth: 2))
            .accessibilityIdentifier("table.winner")
            .accessibilityLabel(Text(verbatim: uiLocalized("winner.a11y", winnerName)))
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Geometry

    /// Places a seat on the ellipse: bottom, then clockwise. Position 0 sits at
    /// the bottom (where the human player will be in M1.7).
    private func seatPosition(for seat: SeatPresentation, in size: CGSize) -> CGPoint {
        let ordered = model.state.seats.sorted { $0.position < $1.position }
        let index = ordered.firstIndex { $0.id == seat.id } ?? 0
        let count = max(ordered.count, 1)
        let angle = (Double(index) / Double(count)) * 2 * .pi + .pi / 2
        let cx = size.width / 2
        let cy = size.height / 2
        let rx = size.width * 0.36
        let ry = size.height * 0.34
        return CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle))
    }

    // MARK: - Text

    private var buttonText: String {
        guard let id = model.state.buttonSeatID, let name = model.names[id] else {
            return uiLocalized("button.none")
        }
        return uiLocalized("button.holder", name)
    }

    private var buttonAccessibility: String {
        guard let id = model.state.buttonSeatID, let name = model.names[id] else {
            return uiLocalized("button.none")
        }
        return uiLocalized("button.a11y", name)
    }

    private var boardAccessibility: String {
        model.state.board.isEmpty
            ? uiLocalized("board.a11y.empty")
            : uiLocalized("board.a11y", CardText.spoken(model.state.board))
    }
}

#if DEBUG
#Preview {
    PokerTableView()
}
#endif
