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
            // IDENTITY — name, chips, status. Needed occasionally, so it is a SEPARATE
            // element and deliberately sorted AFTER the board (D-083).
            VStack(spacing: 4) {
                Text(verbatim: names[seat.id] ?? "")
                    .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(seat.isBusted ? TablePalette.foldedDim : TablePalette.primaryText)
                Text(verbatim: uiLocalized("seat.chips", seat.chips))
                    .font(.caption.monospacedDigit()).foregroundStyle(TablePalette.secondaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: identity(seat, isActive: isActive)))
            .accessibilityIdentifier("opponent.\(seat.id)")
            .accessibilitySortPriority(1)

            // THE BOARD — the read the player performs many times per hand. Its own
            // element, reached in ONE swipe, and sorted FIRST inside the badge (D-083).
            cardsRow(seat)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: board(seat)))
                .accessibilityIdentifier("opponent.\(seat.id).board")
                .accessibilitySortPriority(2)

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
        // The badge is a CONTAINER of two leaves (board, identity), never one merged
        // element — see D-083 and the D-019 gotcha (identifiers live on the leaves).
        .accessibilityElement(children: .contain)
    }

    /// The opponent's visible cards: their UP cards only, sized to fit (D-089).
    ///
    /// The two face-down backs are deliberately gone. They carried no information —
    /// a back is a back — but they cost a third of the row's width, and with them the
    /// band overflowed the phone from fourth street onward. Dropping them lets the
    /// four up cards, which ARE the strategic content of Stud (D-078), stay large
    /// enough to read. That a seat still holds cards is already conveyed: a folded or
    /// busted seat says so in words, right here.
    @ViewBuilder
    private func cardsRow(_ seat: StudSeatPresentation) -> some View {
        if seat.isFolded || seat.isBusted {
            Text(verbatim: uiLocalized(seat.isBusted ? "badge.busted" : "badge.folded"))
                .font(.caption2).foregroundStyle(TablePalette.foldedDim)
                .frame(minHeight: 46)
        } else {
            FittedCardRow(faces: seat.upCards.map { .up($0) })
                .frame(minHeight: 46)
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

    /// THE INTERROGATION (D-083): this opponent's exposed board and NOTHING ELSE
    /// before it — no chips, no status, no "up cards:" preamble. Reading the boards
    /// is the strategic core of Stud and is done many times per hand, so the very
    /// first thing this element says is the cards. Only the owner's name precedes
    /// them, because with two opponents the read is useless without knowing whose it
    /// is — that is identity, not preamble.
    ///
    /// DESCRIBES, NEVER ADVISES (CONVENTIONS §4): the cards as they lie, never what
    /// they might mean.
    private func board(_ seat: StudSeatPresentation) -> String {
        StudBoardReadout.board(name: names[seat.id] ?? "", upCards: seat.upCards,
                               isFolded: seat.isFolded, isBusted: seat.isBusted)
    }

    /// Identity: name, chips and status — needed occasionally, so it lives behind
    /// the board rather than in front of it (D-083).
    private func identity(_ seat: StudSeatPresentation, isActive: Bool) -> String {
        StudBoardReadout.identity(name: names[seat.id] ?? "", chips: seat.chips,
                                  isActive: isActive, isFolded: seat.isFolded,
                                  isBusted: seat.isBusted, isAllIn: seat.isAllIn,
                                  isBringIn: seat.isBringIn)
    }
}

// MARK: - Bottom band: the human's own cards (down + up) + stack

struct StudHeroZoneView: View {
    let state: StudTableState

    private var heroSeat: StudSeatPresentation? {
        state.heroSeatID.flatMap { id in state.seats.first { $0.id == id } }
    }

    /// Name and stack sit ABOVE the cards rather than beside them (D-089): at seventh
    /// street the player holds seven cards, and a side column stole ~90 pt of the width
    /// they need. Stacked, the hand gets the full width of the zone and the cards stay
    /// legible instead of shrinking to fit around the stack.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: uiLocalized("hero.you"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(TablePalette.primaryText)
                Spacer(minLength: 8)
                Text(verbatim: uiLocalized("seat.chips", heroSeat?.chips ?? 0))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(ClockPalette.accent)
                    .accessibilityLabel(Text(verbatim: uiLocalized("hero.stack.a11y", heroSeat?.chips ?? 0)))
                    .voiceOverFocusLanding()   // land VoiceOver on the hero on table entry (D-057)
            }
            cards
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
            VStack(alignment: .leading, spacing: 4) {
                // THE HAND — one element, read as ONE CONTINUOUS WHOLE (D-089). The old
                // label split it in two ("your hole cards: … / showing, seen by all: …"),
                // which both told the player something they already know — in Stud a card
                // that is up is up — and broke a hand the sighted player takes in at a
                // glance into two blocks with a preamble between them.
                FittedCardRow(faces: (down + up).map { .up($0) }, spacing: 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("hero.cards")
                    .accessibilityLabel(Text(verbatim: uiLocalized("stud.hero.cards.a11y",
                                                                   CardText.spoken(down + up))))
                    .accessibilitySortPriority(2)

                // The up/down split stays AVAILABLE, just no longer in the way: its own
                // element, reached on demand, mirroring the opponents' board (D-083).
                Text(verbatim: uiLocalized("stud.hero.showing", up.count))
                    .font(.caption2).foregroundStyle(TablePalette.secondaryText)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("hero.board")
                    .accessibilityLabel(Text(verbatim: up.isEmpty
                        ? uiLocalized("stud.hero.board.none.a11y")
                        : uiLocalized("stud.hero.board.a11y", CardText.spoken(up))))
                    .accessibilitySortPriority(1)
            }
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
