// OmahaTableView.swift
// =====================================================================
// The playable Skypool Omaha Pot Limit table (D-066): a layered screen, sibling of the
// Texas and Draw tables, but for Omaha. The human is the protagonist at the bottom
// with FOUR face-up hole cards; the bots are badges at the top; the centre shows the
// five community cards, the pot, the button, the "Pot Limit" tag and a stakes-up
// banner. The human's raise uses a Pot-Limit-aware box (see OmahaActionBarView).
//
// A pure listener + input forwarder: it renders `OmahaTableViewModel.state` and sends
// taps to the model, which forwards them to the HumanOmahaActionProvider. Accessibility
// is first-class (D-016/D-027/D-057). The centre uses the Skypool's cool marble palette
// — the speciality table's signature look.

import SwiftUI
import GameEngine
import GameWorld
import Audio

/// The Skypool's cool "Marble" look for the Omaha table centre (D-066).
enum MarblePalette {
    static let felt = Color(red: 0.12, green: 0.20, blue: 0.27)      // cool marble slate
    static let feltEdge = Color(red: 0.62, green: 0.80, blue: 0.90)  // pale water edge
    static let accent = Color(red: 0.55, green: 0.82, blue: 0.95)    // cyan/water accent
}

/// The playable Omaha table screen, opened from the Skypool's "Marble" table with a
/// cash-out callback (D-036). Wrapped in GameChrome by the app root.
struct OmahaTableScreen: View {
    @StateObject private var model: OmahaTableViewModel

    init(rules: OmahaTableRules, audio: AudioEngine, mode: AppVoiceOverMode,
         returnLabel: String = uiLocalized("endgame.return.skypool"),
         casinoAudio: CasinoAudio = .skypool, onLeave: @escaping (Int) -> Void) {
        let fastMode = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        // No seed → fresh random cards every hand in production (D-047).
        _model = StateObject(wrappedValue: OmahaTableViewModel(fastMode: fastMode, audio: audio, mode: mode,
                                                               rules: rules, returnLabel: returnLabel,
                                                               casinoAudio: casinoAudio, onLeave: onLeave))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 6) {
                    leaveBar
                    OmahaOpponentBadgesView(state: model.state, names: model.names)
                        .frame(height: geometry.size.height * 0.20)

                    OmahaTableCenterView(state: model.state, names: model.names)
                        .frame(maxHeight: .infinity)

                    OmahaActionBarView(model: model)

                    OmahaHeroZoneView(state: model.state)
                        .frame(height: geometry.size.height * 0.30)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityHidden(model.raiseBox != nil || model.outcome != nil)

                if let box = model.raiseBox {
                    ZStack {
                        Color.black.opacity(0.5).ignoresSafeArea()
                            .onTapGesture { model.cancelRaise() }
                            .accessibilityHidden(true)
                        OmahaRaiseBoxView(model: model, box: box)
                    }
                }

                if let outcome = model.outcome {
                    EndOverlay(outcome: outcome, onReturn: { model.returnToCasino() },
                               returnLabel: model.returnLabel)
                }
            }
        }
        .task { await model.run() }
    }

    private var leaveBar: some View {
        HStack {
            Button { model.requestLeave() } label: {
                Label(uiLocalized("table.leave"), systemImage: "arrow.left.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TablePalette.primaryText)
                    .padding(.horizontal, 10).frame(height: 36)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
            }
            .disabled(model.pendingLeave)
            .accessibilityIdentifier("table.leave")
            .accessibilityHint(Text(uiLocalized("table.leave.hint")))
            Spacer()
            if model.pendingLeave {
                Text(verbatim: uiLocalized("table.leave.pending"))
                    .font(.caption).foregroundStyle(MarblePalette.accent)
                    .accessibilityIdentifier("table.leave.pending")
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Centre: community cards, pot, button, Pot-Limit tag

struct OmahaTableCenterView: View {
    let state: OmahaTableState
    let names: [Int: String]

    var body: some View {
        ZStack {
            Ellipse()
                .fill(MarblePalette.felt)
                .overlay(Ellipse().strokeBorder(MarblePalette.feltEdge, lineWidth: 3))
                .accessibilityElement()
                .accessibilityIdentifier("omahatable.container")
                .accessibilityLabel(Text(verbatim: uiLocalized("omaha.table.a11y")))

            VStack(spacing: 8) {
                potLimitTag
                buttonIndicator
                board
                pot
                if state.escalated { stakesBanner }
            }
            .padding(.horizontal, 12)
        }
    }

    private var potLimitTag: some View {
        Text(verbatim: uiLocalized("omaha.potlimit.tag"))
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(MarblePalette.accent.opacity(0.25)))
            .foregroundStyle(MarblePalette.accent)
            .accessibilityHidden(true)   // the table label already says "Pot Limit"
    }

    private var buttonIndicator: some View {
        Text(verbatim: buttonText)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(MarblePalette.accent)
            .accessibilityIdentifier("omahatable.button")
            .accessibilityLabel(Text(verbatim: buttonA11y))
    }

    private var board: some View {
        HStack(spacing: 6) {
            if state.board.isEmpty {
                Text(verbatim: uiLocalized("board.empty"))
                    .font(.subheadline).foregroundStyle(TablePalette.secondaryText)
            } else {
                ForEach(Array(state.board.enumerated()), id: \.offset) { _, card in
                    CardView(face: .up(card))
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("omahatable.board")
        .accessibilityLabel(Text(verbatim: boardA11y))
    }

    private var pot: some View {
        Text(verbatim: uiLocalized("pot.label", state.pot))
            .font(.headline.monospacedDigit())
            .foregroundStyle(TablePalette.primaryText)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.4)))
            .overlay(Capsule().strokeBorder(MarblePalette.accent.opacity(0.7), lineWidth: 1))
            .accessibilityIdentifier("omahatable.pot")
            .accessibilityLabel(Text(verbatim: uiLocalized("pot.a11y", state.pot)))
    }

    private var stakesBanner: some View {
        Text(verbatim: uiLocalized("omaha.stakes.banner"))
            .font(.caption.weight(.heavy)).foregroundStyle(.black)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(MarblePalette.accent))
            .accessibilityIdentifier("omahatable.stakes")
            .accessibilityLabel(Text(verbatim: uiLocalized("omaha.stakes.a11y", state.smallBlind, state.bigBlind)))
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

// MARK: - Top band: opponents

struct OmahaOpponentBadgesView: View {
    let state: OmahaTableState
    let names: [Int: String]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(state.opponents, id: \.id) { seat in badge(for: seat) }
        }
        .frame(maxWidth: .infinity)
    }

    private func badge(for seat: OmahaSeatPresentation) -> some View {
        let isActive = state.activeSeatID == seat.id
        return VStack(spacing: 3) {
            Text(verbatim: names[seat.id] ?? "")
                .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(seat.isBusted ? TablePalette.foldedDim : TablePalette.primaryText)
            Text(verbatim: uiLocalized("seat.chips", seat.chips))
                .font(.caption.monospacedDigit()).foregroundStyle(TablePalette.secondaryText)
            statusLine(seat)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8).padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(isActive ? 0.5 : 0.28))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isActive ? MarblePalette.accent : Color.white.opacity(0.12),
                                  lineWidth: isActive ? 2.5 : 1)))
        .opacity(seat.isFolded && !seat.isBusted ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: summary(seat, isActive: isActive)))
        .accessibilityIdentifier("opponent.\(seat.id)")
    }

    @ViewBuilder
    private func statusLine(_ seat: OmahaSeatPresentation) -> some View {
        HStack(spacing: 4) {
            if seat.isButton { pill(uiLocalized("badge.button"), MarblePalette.accent, .black) }
            if seat.isBusted { pill(uiLocalized("badge.busted"), TablePalette.foldedDim, .black) }
            else if seat.isAllIn { pill(uiLocalized("badge.allIn"), TablePalette.redSuit, .white) }
            else if seat.isFolded { pill(uiLocalized("badge.folded"), Color.white.opacity(0.25), .white) }
        }
        .accessibilityHidden(true)
    }

    private func pill(_ text: String, _ background: Color, _ foreground: Color) -> some View {
        Text(verbatim: text).font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(background)).foregroundStyle(foreground)
    }

    private func summary(_ seat: OmahaSeatPresentation, isActive: Bool) -> String {
        var parts = [uiLocalized("seat.a11y.base", names[seat.id] ?? "", seat.chips)]
        if isActive { parts.append(uiLocalized("seat.a11y.acting")) }
        if seat.isButton { parts.append(uiLocalized("seat.a11y.button")) }
        if seat.isBusted { parts.append(uiLocalized("seat.a11y.busted")) }
        else if seat.isAllIn { parts.append(uiLocalized("seat.a11y.allIn")) }
        else if seat.isFolded { parts.append(uiLocalized("seat.a11y.folded")) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Bottom band: the human's four hole cards + stack

struct OmahaHeroZoneView: View {
    let state: OmahaTableState

    private var heroSeat: OmahaSeatPresentation? {
        state.heroSeatID.flatMap { id in state.seats.first { $0.id == id } }
    }

    var body: some View {
        HStack(spacing: 12) {
            cards
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: uiLocalized("hero.you"))
                    .font(.headline).foregroundStyle(TablePalette.primaryText)
                Text(verbatim: uiLocalized("seat.chips", heroSeat?.chips ?? 0))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(MarblePalette.accent)
                    .accessibilityLabel(Text(verbatim: uiLocalized("hero.stack.a11y", heroSeat?.chips ?? 0)))
                    .voiceOverFocusLanding()   // land VoiceOver on the hero on table entry (D-057)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(MarblePalette.accent.opacity(0.6), lineWidth: 1.5)))
    }

    @ViewBuilder
    private var cards: some View {
        if let hole = state.heroCards, hole.count == 4 {
            HStack(spacing: 5) {
                ForEach(Array(hole.enumerated()), id: \.offset) { _, card in
                    CardView(face: .up(card), size: .medium)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("hero.cards")
            // Grouped BY SUIT so the player hears suitedness without drowning (D-066).
            .accessibilityLabel(Text(verbatim: uiLocalized("omaha.hero.cards.a11y", OmahaSpeechMap.omahaHoleSpoken(hole))))
        } else {
            Text(verbatim: uiLocalized("hero.nocards"))
                .font(.subheadline).foregroundStyle(TablePalette.secondaryText)
                .frame(minHeight: 74)
                .accessibilityIdentifier("hero.cards")
                .accessibilityLabel(Text(verbatim: uiLocalized("omaha.nocards.a11y")))
        }
    }
}

#if DEBUG
#Preview {
    AppRootView()
}
#endif
