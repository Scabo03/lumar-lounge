// BlackjackTableView.swift
// =====================================================================
// The blackjack table.
//
// The accessibility shape follows D-083/D-089: the information consulted
// most often — YOUR TOTAL and the DEALER'S UP CARD — leads, and the cards
// that make it up follow on the same element rather than in a separate
// announcement. Nothing here re-states what the compact deal line already
// said; the elements exist so the player can go BACK for detail when they
// want it, which is the memory a sighted player has by simply looking.

import SwiftUI
import GameEngine
import GameWorld
import Audio

// THE READING ORDER IS DECLARED, NOT INHERITED (D-096).
// Left to geometry, a swipe forward from the player's stack jumped to the top of
// the screen — the test banner, the settings button, "leave table" — and only
// then came the five moves, which is the opposite of what the round needs. The
// whole screen now carries explicit sort priorities, highest read first:
//   dealer 100 · hand total 90 · hand cards 85 · the five moves 70…66 ·
//   stakes 40 · leave 5
// so the player goes from what they hold straight to what they can do about it,
// and the fiches line no longer sits between the hand and the moves (D-098).
struct BlackjackTableScreen: View {
    @StateObject private var model: BlackjackTableViewModel

    init(rules: BlackjackTableRules,
         audio: AudioEngine,
         mode: AppVoiceOverMode,
         returnLabel: String = uiLocalized("endgame.return"),
         casinoAudio: CasinoAudio = .riverwood,
         onLeave: @escaping (Int) -> Void) {
        let fastMode = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        _model = StateObject(wrappedValue: BlackjackTableViewModel(fastMode: fastMode,
                                                                   audio: audio,
                                                                   mode: mode,
                                                                   rules: rules,
                                                                   returnLabel: returnLabel,
                                                                   casinoAudio: casinoAudio,
                                                                   onLeave: onLeave))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 8) {
                    leaveBar
                    BlackjackDealerZoneView(state: model.state)
                        .frame(height: geometry.size.height * 0.26)
                    Spacer(minLength: 0)
                    BlackjackHeroZoneView(state: model.state)
                    BlackjackActionBarView(model: model)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityHidden(model.betBox != nil || model.outcome != nil)

                if let box = model.betBox {
                    ZStack {
                        Color.black.opacity(0.55).ignoresSafeArea()
                            .accessibilityHidden(true)
                        BlackjackBetBoxView(model: model, box: box)
                    }
                }

                if let outcome = model.outcome {
                    EndOverlay(outcome: outcome,
                               onReturn: { model.returnToCasino() },
                               returnLabel: model.returnLabel)
                }
            }
        }
        .task { await model.run() }
    }

    private var leaveBar: some View {
        HStack {
            Button(action: { model.requestLeave() }) {
                Text(verbatim: uiLocalized("table.leave"))
                    .font(.subheadline)
                    .foregroundColor(TablePalette.secondaryText)
            }
            .accessibilityIdentifier("table.leave")
            .accessibilityHint(Text(verbatim: uiLocalized("table.leave.hint")))
            .accessibilitySortPriority(5)
            Spacer()
        }
    }
}

// MARK: - The dealer

private struct BlackjackDealerZoneView: View {
    let state: BlackjackTableState

    var body: some View {
        VStack(spacing: 4) {
            Text(verbatim: uiLocalized("blackjack.dealer.title"))
                .font(.caption)
                .foregroundColor(TablePalette.secondaryText)
                .accessibilityHidden(true)

            FittedCardRow(faces: dealerFaces)
                .frame(minHeight: 46)

            Text(verbatim: dealerCaption)
                .font(.headline)
                .foregroundColor(TablePalette.primaryText)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        // One leaf, whose LABEL changes with the state — never a subtree that
        // grows and shrinks, so VoiceOver focus is never dislodged (D-046).
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("blackjack.dealer")
        .accessibilityLabel(Text(verbatim: BlackjackReadout.dealer(cards: state.dealerCards,
                                                                  holeCardHidden: state.holeCardHidden,
                                                                  hasNatural: state.dealerHasNatural,
                                                                  didBust: state.dealerBusted)))
        .accessibilitySortPriority(100)
    }

    /// While the hole card is down it is shown as a card back — the player can
    /// see there is one, exactly as at a real table.
    private var dealerFaces: [CardView.Face] {
        guard !state.dealerCards.isEmpty else { return [] }
        var faces = state.dealerCards.map { CardView.Face.up($0) }
        if state.holeCardHidden { faces.append(.down) }
        return faces
    }

    private var dealerCaption: String {
        guard !state.dealerCards.isEmpty else { return "" }
        if state.holeCardHidden { return "\(state.dealerTotal) +" }
        return "\(state.dealerTotal)"
    }
}

// MARK: - The player

private struct BlackjackHeroZoneView: View {
    let state: BlackjackTableState

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(state.hands.enumerated()), id: \.offset) { index, hand in
                handView(hand, index: index)
            }

            // The stakes read sits AFTER the hand and the moves (priority 40), so a
            // swipe from the hand reaches the actions directly instead of detouring
            // through the fiches line (D-098). It still catches focus on TABLE ENTRY,
            // which the focus-landing modifier does regardless of sort order.
            Text(verbatim: BlackjackReadout.stakes(chips: state.chips, atStake: state.totalAtStake))
                .font(.subheadline)
                .foregroundColor(TablePalette.secondaryText)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("blackjack.stakes")
                .accessibilityLabel(Text(verbatim: BlackjackReadout.stakes(chips: state.chips,
                                                                          atStake: state.totalAtStake)))
                .accessibilitySortPriority(40)
                .voiceOverFocusLanding()
        }
        .frame(maxWidth: .infinity)
    }

    /// The hand is TWO accessible elements (D-098): the TOTAL — the focus target
    /// and the short automatic read — and the CARDS behind it, one swipe away for a
    /// player studying the hand. Splitting them keeps the auto-read to the number,
    /// which is what the player needs to decide and what never gets cut off.
    private func handView(_ hand: BlackjackHandPresentation, index: Int) -> some View {
        VStack(spacing: 3) {
            FittedCardRow(faces: hand.cards.map { .up($0) })
                .frame(minHeight: 46)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(state.hasSplit ? "blackjack.hand.\(index).cards" : "blackjack.hand.cards")
                .accessibilityLabel(Text(verbatim: BlackjackReadout.handCards(hand)))
                .accessibilitySortPriority(85 - Double(index) * 2)

            Text(verbatim: caption(hand))
                .font(.headline)
                .foregroundColor(state.activeHandIndex == index
                                 ? TablePalette.accent : TablePalette.primaryText)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(state.hasSplit ? "blackjack.hand.\(index)" : "blackjack.hand")
                .accessibilityLabel(Text(verbatim: BlackjackReadout.total(hand,
                                                                          index: index,
                                                                          handCount: state.hands.count)))
                .accessibilitySortPriority(90 - Double(index) * 2)
                // Where focus goes when the wager box vanishes (D-092). Every round
                // starts by pressing Confirm, which then ceases to exist with the
                // cursor on it; the hand is dealt a moment later, so claiming focus
                // as the TOTAL appears puts the player on the amount at once — no
                // swipe between deciding the wager and hearing the hand. Only the
                // FIRST hand claims: a split must not yank the cursor off a hand
                // still being played.
                .voiceOverFocusClaim(index == 0)
        }
        .padding(.vertical, 2)
    }

    private func caption(_ hand: BlackjackHandPresentation) -> String {
        let total = hand.isSoft
            ? uiLocalized("blackjack.total.soft", hand.total)
            : uiLocalized("blackjack.total.hard", hand.total)
        guard let outcome = hand.outcome else { return total }
        return "\(total) · \(BlackjackTableView.outcomeCaption(outcome))"
    }
}

/// Small shared helpers, kept out of the view bodies so they stay testable.
enum BlackjackTableView {
    static func outcomeCaption(_ outcome: BlackjackOutcome) -> String {
        switch outcome {
        case .natural:   return uiLocalized("blackjack.outcome.natural")
        case .win:       return uiLocalized("blackjack.outcome.win")
        case .push:      return uiLocalized("blackjack.outcome.push")
        case .lose:      return uiLocalized("blackjack.outcome.lose")
        case .bust:      return uiLocalized("blackjack.outcome.bust")
        case .surrender: return uiLocalized("blackjack.outcome.surrender")
        }
    }
}
