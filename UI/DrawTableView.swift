// DrawTableView.swift
// =====================================================================
// The playable Five-Card Draw table (D-044): a layered screen coherent with the
// Texas table but for draw poker. The human is the protagonist at the bottom with
// FIVE face-up cards; the bots are badges at the top; the centre shows the pot, the
// progressive carried pot, the button and the current phase. During the draw a
// dedicated modal box (`DrawBoxView`) opens for the human's card exchange.
//
// A pure listener + input forwarder: it renders `DrawTableViewModel.state` and
// sends taps to the model, which forwards them to the HumanDrawActionProvider.
// Accessibility is first-class (D-016/D-027).

import SwiftUI
import GameEngine
import GameWorld
import Audio

/// The playable draw table screen, opened from the Riverwood's "Sala Whiskey"
/// with a cash-out callback (D-036). Wrapped in GameChrome by the app root.
struct DrawTableScreen: View {
    @StateObject private var model: DrawTableViewModel

    init(rules: DrawTableRules, audio: AudioEngine, mode: AppVoiceOverMode,
         returnLabel: String = uiLocalized("endgame.return"), onLeave: @escaping (Int) -> Void) {
        let fastMode = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        // No seed → fresh random cards every deal in production (D-047).
        _model = StateObject(wrappedValue: DrawTableViewModel(fastMode: fastMode, audio: audio, mode: mode,
                                                              rules: rules, returnLabel: returnLabel, onLeave: onLeave))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 6) {
                    leaveBar
                    DrawOpponentBadgesView(state: model.state, names: model.names)
                        .frame(height: geometry.size.height * 0.20)

                    DrawTableCenterView(state: model.state, names: model.names)
                        .frame(maxHeight: .infinity)

                    DrawActionBarView(model: model)

                    DrawHeroZoneView(state: model.state)
                        .frame(height: geometry.size.height * 0.30)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityHidden(model.drawBox != nil || model.outcome != nil)

                if let box = model.drawBox {
                    ZStack {
                        Color.black.opacity(0.55).ignoresSafeArea()
                            .accessibilityHidden(true)
                        DrawBoxView(model: model, box: box)
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
                    .font(.caption).foregroundStyle(TablePalette.accent)
                    .accessibilityIdentifier("table.leave.pending")
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Centre: pot, progressive pot, button, phase

struct DrawTableCenterView: View {
    let state: DrawTableState
    let names: [Int: String]

    var body: some View {
        ZStack {
            Ellipse()
                .fill(TablePalette.felt)
                .overlay(Ellipse().strokeBorder(TablePalette.feltEdge, lineWidth: 3))
                .accessibilityElement()
                .accessibilityIdentifier("drawtable.container")
                .accessibilityLabel(Text(verbatim: uiLocalized("draw.table.a11y")))

            VStack(spacing: 10) {
                phaseIndicator
                buttonIndicator
                potView
                if state.decisive { decisiveBanner }
                if state.passedIn { passedBanner }
            }
            .padding(.horizontal, 12)
        }
    }

    private var phaseIndicator: some View {
        Text(verbatim: phaseText)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(TablePalette.secondaryText)
            .accessibilityIdentifier("drawtable.phase")
            .accessibilityLabel(Text(verbatim: phaseText))
    }

    private var buttonIndicator: some View {
        Text(verbatim: buttonText)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(TablePalette.accent)
            .accessibilityIdentifier("drawtable.button")
            .accessibilityLabel(Text(verbatim: buttonA11y))
    }

    private var potView: some View {
        VStack(spacing: 2) {
            Text(verbatim: uiLocalized("pot.label", state.pot))
                .font(.headline.monospacedDigit())
                .foregroundStyle(TablePalette.primaryText)
            if state.ante > 0 {
                Text(verbatim: uiLocalized("draw.ante.label", state.ante))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(TablePalette.secondaryText)
                    .accessibilityIdentifier("drawtable.ante")
            }
            if state.carriedPot > 0 {
                Text(verbatim: uiLocalized("draw.pot.carried", state.carriedPot))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(TablePalette.accent)
                    .accessibilityIdentifier("drawtable.carried")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.4)))
        .overlay(Capsule().strokeBorder(TablePalette.accent.opacity(0.7), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("drawtable.pot")
        .accessibilityLabel(Text(verbatim: potA11y))
    }

    private var decisiveBanner: some View {
        Text(verbatim: uiLocalized("draw.decisive.banner"))
            .font(.caption.weight(.heavy))
            .foregroundStyle(.black)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(TablePalette.redSuit).overlay(Capsule().fill(Color.orange.opacity(0.9))))
            .accessibilityIdentifier("drawtable.decisive")
            .accessibilityLabel(Text(verbatim: uiLocalized("draw.decisive.a11y")))
    }

    private var passedBanner: some View {
        Text(verbatim: uiLocalized("draw.passedin.banner"))
            .font(.caption.weight(.bold))
            .foregroundStyle(TablePalette.accent)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.5)))
            .accessibilityIdentifier("drawtable.passedin")
    }

    private var phaseText: String {
        switch state.phase {
        case .idle, .finished: return ""
        case .firstBet: return uiLocalized("draw.phase.firstbet")
        case .draw: return uiLocalized("draw.phase.draw")
        case .secondBet: return uiLocalized("draw.phase.secondbet")
        }
    }
    private var buttonText: String {
        guard let id = state.buttonSeatID, let name = names[id] else { return uiLocalized("button.none") }
        return uiLocalized("button.holder", name)
    }
    private var buttonA11y: String {
        guard let id = state.buttonSeatID, let name = names[id] else { return uiLocalized("button.none") }
        return uiLocalized("button.a11y", name)
    }
    private var potA11y: String {
        let base = state.carriedPot > 0
            ? uiLocalized("draw.pot.a11y.carried", state.pot, state.carriedPot)
            : uiLocalized("pot.a11y", state.pot)
        return state.ante > 0 ? base + ", " + uiLocalized("draw.ante.a11y", state.ante) : base
    }
}

// MARK: - Top band: opponents

struct DrawOpponentBadgesView: View {
    let state: DrawTableState
    let names: [Int: String]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(state.opponents, id: \.id) { seat in badge(for: seat) }
        }
        .frame(maxWidth: .infinity)
    }

    private func badge(for seat: DrawSeatPresentation) -> some View {
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
                    .strokeBorder(isActive ? TablePalette.accent : Color.white.opacity(0.12),
                                  lineWidth: isActive ? 2.5 : 1)))
        .opacity(seat.isFolded && !seat.isBusted ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: summary(seat, isActive: isActive)))
        .accessibilityIdentifier("opponent.\(seat.id)")
    }

    @ViewBuilder
    private func statusLine(_ seat: DrawSeatPresentation) -> some View {
        HStack(spacing: 4) {
            if seat.isButton { pill(uiLocalized("badge.button"), TablePalette.accent, .black) }
            if seat.isOpener { pill(uiLocalized("draw.badge.opener"), TablePalette.accent.opacity(0.9), .black) }
            if let d = seat.discardCount { pill(uiLocalized("draw.badge.drew", d), .white.opacity(0.85), .black) }
            if seat.isDisqualified { pill(uiLocalized("draw.badge.disqualified"), TablePalette.redSuit, .white) }
            else if seat.isBusted { pill(uiLocalized("badge.busted"), TablePalette.foldedDim, .black) }
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

    private func summary(_ seat: DrawSeatPresentation, isActive: Bool) -> String {
        var parts = [uiLocalized("seat.a11y.base", names[seat.id] ?? "", seat.chips)]
        // THE GAME-SPECIFIC READ FIRST (D-083, mild form of the Stud defect): at a
        // draw table what a player wants from an opponent badge is how many cards it
        // exchanged and whether it opened — so those come immediately after the name,
        // ahead of position and status. Not split into its own element as in Stud:
        // this is read about once per hand (and is announced live when it happens),
        // not many times per hand, so a separate swipe stop would be clutter.
        if seat.isOpener { parts.append(uiLocalized("draw.a11y.opener")) }
        if let d = seat.discardCount {
            parts.append(d == 0 ? uiLocalized("draw.a11y.standpat") : uiLocalized("draw.a11y.drew", d))
        }
        if isActive { parts.append(uiLocalized("seat.a11y.acting")) }
        if seat.isButton { parts.append(uiLocalized("seat.a11y.button")) }
        if seat.isDisqualified { parts.append(uiLocalized("draw.a11y.disqualified")) }
        else if seat.isBusted { parts.append(uiLocalized("seat.a11y.busted")) }
        else if seat.isAllIn { parts.append(uiLocalized("seat.a11y.allIn")) }
        else if seat.isFolded { parts.append(uiLocalized("seat.a11y.folded")) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Bottom band: the human's five cards + stack

struct DrawHeroZoneView: View {
    let state: DrawTableState

    private var heroSeat: DrawSeatPresentation? {
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
                    .foregroundStyle(TablePalette.accent)
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
                    .strokeBorder(TablePalette.accent.opacity(0.6), lineWidth: 1.5)))
    }

    @ViewBuilder
    private var cards: some View {
        if let hole = state.heroCards, hole.count == 5 {
            HStack(spacing: 5) {
                ForEach(Array(hole.enumerated()), id: \.offset) { _, card in
                    CardView(face: .up(card), size: .medium)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("hero.cards")
            .accessibilityLabel(Text(verbatim: uiLocalized("hero.cards.a11y", CardText.spoken(hole))))
        } else {
            Text(verbatim: uiLocalized("hero.nocards"))
                .font(.subheadline).foregroundStyle(TablePalette.secondaryText)
                .frame(minHeight: 74)
                .accessibilityIdentifier("hero.cards")
                .accessibilityLabel(Text(verbatim: uiLocalized("hero.nocards.a11y")))
        }
    }
}

#if DEBUG
#Preview {
    AppRootView()
}
#endif
