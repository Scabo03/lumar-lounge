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
        .accessibilitySortPriority(3)
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
            Text(verbatim: BlackjackReadout.stakes(chips: state.chips, atStake: state.totalAtStake))
                .font(.subheadline)
                .foregroundColor(TablePalette.secondaryText)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("blackjack.stakes")
                .accessibilityLabel(Text(verbatim: BlackjackReadout.stakes(chips: state.chips,
                                                                          atStake: state.totalAtStake)))
                .accessibilitySortPriority(1)
                .voiceOverFocusLanding()

            ForEach(Array(state.hands.enumerated()), id: \.offset) { index, hand in
                handView(hand, index: index)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func handView(_ hand: BlackjackHandPresentation, index: Int) -> some View {
        VStack(spacing: 3) {
            FittedCardRow(faces: hand.cards.map { .up($0) })
                .frame(minHeight: 46)

            Text(verbatim: caption(hand))
                .font(.headline)
                .foregroundColor(state.activeHandIndex == index
                                 ? TablePalette.accent : TablePalette.primaryText)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(state.hasSplit ? "blackjack.hand.\(index)" : "blackjack.hand")
        .accessibilityLabel(Text(verbatim: BlackjackReadout.hand(hand,
                                                                 index: index,
                                                                 handCount: state.hands.count)))
        .accessibilitySortPriority(2)
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
