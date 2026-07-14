// StudTableView.swift
// =====================================================================
// The playable ClockTower Seven-Card Stud Pot Limit table (D-077): a layered screen,
// sibling of the other poker tables. The human is the protagonist at the bottom with
// their DOWN cards (private, shown face-up to them) and UP cards; the two opponents are
// badges at the top; the centre shows the pot, the ante/bring-in/bet, the street, and the
// House-Prize banner.
//
// THE ACCESSIBILITY CENTREPIECE (D-078). Stud has no shared board — each player has
// DIFFERENT up cards, and reading them is the game. A sighted player sees all the boards
// at once; a blind player can't hold them in memory. So:
//   1. Every up card is ANNOUNCED as it is dealt (parity — the sighted player sees it
//      appear), by the view model.
//   2. Each opponent badge is an ON-DEMAND INTERROGATION: swiping to it reads that
//      opponent's NAME, chips, status, AND their current up cards ("scoperte: re di cuori,
//      dieci di picche") — the full recall the sighted player gets with a glance. It
//      DESCRIBES the public cards; it never ADVISES. The label is derived from the current
//      state, never a frozen snapshot (D-058 spirit), so it always reflects the live board.

import SwiftUI
import GameEngine
import GameWorld
import Audio

/// The playable Stud table screen, opened from the ClockTower's Stud table with a
/// cash-out callback (D-036). Wrapped in GameChrome by the app root.
struct StudTableScreen: View {
    @StateObject private var model: StudTableViewModel

    init(rules: StudTableRules, audio: AudioEngine, mode: AppVoiceOverMode,
         returnLabel: String = uiLocalized("endgame.return.clocktower"),
         casinoAudio: CasinoAudio = .clockTower, onLeave: @escaping (Int) -> Void) {
        let fastMode = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        _model = StateObject(wrappedValue: StudTableViewModel(fastMode: fastMode, audio: audio, mode: mode,
                                                              rules: rules, returnLabel: returnLabel,
                                                              casinoAudio: casinoAudio, onLeave: onLeave))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 6) {
                    leaveBar
                    StudOpponentBadgesView(state: model.state, names: model.names)
                        .frame(height: geometry.size.height * 0.30)

                    StudTableCenterView(state: model.state)
                        .frame(maxHeight: .infinity)

                    StudActionBarView(model: model)

                    StudHeroZoneView(state: model.state)
                        .frame(height: geometry.size.height * 0.24)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityHidden(model.raiseBox != nil || model.outcome != nil)

                if let box = model.raiseBox {
                    ZStack {
                        Color.black.opacity(0.5).ignoresSafeArea()
                            .onTapGesture { model.cancelRaise() }
                            .accessibilityHidden(true)
                        StudRaiseBoxView(model: model, box: box)
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
                    .font(.caption).foregroundStyle(ClockPalette.accent)
                    .accessibilityIdentifier("table.leave.pending")
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Centre: pot, stakes, street, House-Prize banner

struct StudTableCenterView: View {
    let state: StudTableState

    var body: some View {
        ZStack {
            Ellipse()
                .fill(ClockPalette.felt)
                .overlay(Ellipse().strokeBorder(ClockPalette.feltEdge, lineWidth: 3))
                .accessibilityElement()
                .accessibilityIdentifier("studtable.container")
                .accessibilityLabel(Text(verbatim: uiLocalized("stud.table.a11y")))

            VStack(spacing: 8) {
                Text(verbatim: uiLocalized("stud.potlimit.tag"))
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(ClockPalette.accent.opacity(0.25)))
                    .foregroundStyle(ClockPalette.accent)
                    .accessibilityHidden(true)

                streetLabel
                pot
                stakesLabel
                if let community = state.communityCard { communityView(community) }
                // No in-play prize banner (D-079): the House Prize is invisible at the table
                // — it is a cash-out reward for beating the whole table, not a per-hand event.
            }
            .padding(.horizontal, 12)
        }
    }

    private var streetLabel: some View {
        Text(verbatim: streetText)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(ClockPalette.accent)
            .accessibilityIdentifier("studtable.street")
            .accessibilityLabel(Text(verbatim: streetText))
    }

    private var pot: some View {
        Text(verbatim: uiLocalized("pot.label", state.pot))
            .font(.headline.monospacedDigit())
            .foregroundStyle(TablePalette.primaryText)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.4)))
            .overlay(Capsule().strokeBorder(ClockPalette.accent.opacity(0.7), lineWidth: 1))
            .accessibilityIdentifier("studtable.pot")
            .accessibilityLabel(Text(verbatim: uiLocalized("pot.a11y", state.pot)))
    }

    private var stakesLabel: some View {
        Text(verbatim: uiLocalized("stud.stakes", state.ante, state.bringIn, state.bet))
            .font(.caption.monospacedDigit()).foregroundStyle(TablePalette.secondaryText)
            .accessibilityIdentifier("studtable.stakes")
            .accessibilityLabel(Text(verbatim: uiLocalized("stud.stakes.a11y", state.ante, state.bringIn, state.bet)))
    }

    private func communityView(_ card: Card) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: uiLocalized("stud.community")).font(.caption).foregroundStyle(TablePalette.secondaryText)
            CardView(face: .up(card))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("studtable.community")
        .accessibilityLabel(Text(verbatim: uiLocalized("stud.community.a11y", CardText.spoken(card))))
    }


    private var streetText: String {
        switch state.street {
        case .third:   return uiLocalized("stud.street.3")
        case .fourth:  return uiLocalized("stud.street.4")
        case .fifth:   return uiLocalized("stud.street.5")
        case .sixth:   return uiLocalized("stud.street.6")
        case .seventh: return uiLocalized("stud.street.7")
        case .none:    return uiLocalized("stud.street.none")
        }
    }
}

// MARK: - Top band: opponents (the on-demand interrogation)

struct StudOpponentBadgesView: View {
    let state: StudTableState
    let names: [Int: String]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(state.opponents, id: \.id) { seat in badge(for: seat) }
        }
        .frame(maxWidth: .infinity)
    }

    private func badge(for seat: StudSeatPresentation) -> some View {
        let isActive = state.activeSeatID == seat.id
        return VStack(spacing: 4) {
            Text(verbatim: names[seat.id] ?? "")
                .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(seat.isBusted ? TablePalette.foldedDim : TablePalette.primaryText)
            Text(verbatim: uiLocalized("seat.chips", seat.chips))
                .font(.caption.monospacedDigit()).foregroundStyle(TablePalette.secondaryText)
            cardsRow(seat)
            statusLine(seat)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8).padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(isActive ? 0.5 : 0.28))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isActive ? ClockPalette.accent : Color.white.opacity(0.12),
                                  lineWidth: isActive ? 2.5 : 1)))
        .opacity(seat.isFolded && !seat.isBusted ? 0.5 : 1)
        // The whole badge is ONE accessibility element: the on-demand interrogation of
        // this opponent's board (name, chips, status, up cards). Describes, never advises.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: summary(seat, isActive: isActive)))
        .accessibilityIdentifier("opponent.\(seat.id)")
    }

    /// The opponent's visible cards: their up cards face-up + a couple of down-card backs.
    @ViewBuilder
    private func cardsRow(_ seat: StudSeatPresentation) -> some View {
        if seat.isFolded || seat.isBusted {
            Text(verbatim: uiLocalized(seat.isBusted ? "badge.busted" : "badge.folded"))
                .font(.caption2).foregroundStyle(TablePalette.foldedDim)
                .frame(minHeight: 46)
        } else {
            HStack(spacing: 3) {
                if seat.hasCards {
                    CardView(face: .down)
                    CardView(face: .down)
                }
                ForEach(Array(seat.upCards.enumerated()), id: \.offset) { _, card in
                    CardView(face: .up(card))
                }
            }
        }
    }

    @ViewBuilder
    private func statusLine(_ seat: StudSeatPresentation) -> some View {
        HStack(spacing: 4) {
            if seat.isBringIn && !seat.isFolded { pill(uiLocalized("stud.badge.bringin"), ClockPalette.accent, .black) }
            if seat.isAllIn && !seat.isBusted { pill(uiLocalized("badge.allIn"), TablePalette.redSuit, .white) }
        }
        .accessibilityHidden(true)
    }

    private func pill(_ text: String, _ background: Color, _ foreground: Color) -> some View {
        Text(verbatim: text).font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(background)).foregroundStyle(foreground)
    }

    private func summary(_ seat: StudSeatPresentation, isActive: Bool) -> String {
        var parts = [uiLocalized("seat.a11y.base", names[seat.id] ?? "", seat.chips)]
        if isActive { parts.append(uiLocalized("seat.a11y.acting")) }
        if seat.isBusted { parts.append(uiLocalized("seat.a11y.busted")) }
        else if seat.isFolded { parts.append(uiLocalized("seat.a11y.folded")) }
        else {
            if seat.isAllIn { parts.append(uiLocalized("seat.a11y.allIn")) }
            if seat.isBringIn { parts.append(uiLocalized("stud.seat.bringin.a11y")) }
            // THE interrogation: this opponent's exposed board, read on demand.
            if !seat.upCards.isEmpty {
                parts.append(uiLocalized("stud.seat.upcards.a11y", CardText.spoken(seat.upCards)))
            }
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Bottom band: the human's own cards (down + up) + stack

struct StudHeroZoneView: View {
    let state: StudTableState

    private var heroSeat: StudSeatPresentation? {
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
                    .foregroundStyle(ClockPalette.accent)
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
                    .strokeBorder(ClockPalette.accent.opacity(0.6), lineWidth: 1.5)))
    }

    @ViewBuilder
    private var cards: some View {
        if let down = state.heroDown, !down.isEmpty {
            let up = heroSeat?.upCards ?? []
            HStack(spacing: 5) {
                ForEach(Array(down.enumerated()), id: \.offset) { _, card in
                    CardView(face: .up(card), size: .medium)
                }
                if !up.isEmpty {
                    Rectangle().fill(ClockPalette.accent.opacity(0.5)).frame(width: 1, height: 60)
                    ForEach(Array(up.enumerated()), id: \.offset) { _, card in
                        CardView(face: .up(card))
                    }
                }
            }
            // One element distinguishing the hero's DOWN (private) cards from their UP
            // (public) cards, so the blind player knows what everyone else can read.
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("hero.cards")
            .accessibilityLabel(Text(verbatim: uiLocalized("stud.hero.cards.a11y",
                                                            CardText.spoken(down),
                                                            up.isEmpty ? uiLocalized("stud.hero.noup") : CardText.spoken(up))))
        } else {
            Text(verbatim: uiLocalized("hero.nocards"))
                .font(.subheadline).foregroundStyle(TablePalette.secondaryText)
                .frame(minHeight: 74)
                .accessibilityIdentifier("hero.cards")
                .accessibilityLabel(Text(verbatim: uiLocalized("stud.hero.nocards.a11y")))
        }
    }
}

#if DEBUG
#Preview {
    AppRootView()
}
#endif
