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

// THE READING ORDER IS DECLARED, NOT INHERITED (D-096/D-100).
// Left to geometry, a swipe forward from the player's stack jumped to the top of
// the screen — the test banner, the settings button, "leave table" — and only then
// came the five moves. The whole screen carries explicit sort priorities, highest
// read first:
//   dealer 100 · hand TOTAL 90 · the five moves 70…66 · hand CARDS 50 ·
//   stakes 40 · leave 5
// The one firm rule (D-100): from the hand's TOTAL, a swipe goes STRAIGHT to the
// moves. The cards behind the total, and the fiches line, come AFTER the moves —
// reachable for a player who wants them, never in the way of deciding.
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

            // The dealer's total, LARGE (D-100): it is half of what every decision
            // turns on, so it reads at a glance rather than as fine print.
            Text(verbatim: dealerCaption)
                .font(.system(size: 46, weight: .heavy, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
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
        VStack(spacing: 1) {
            // THE TOTAL, LARGE — the focus target and the number the player decides on
            // (D-100). It reads first (sort 90) and a swipe from it goes STRAIGHT to the
            // action buttons; the cards it is made of sit BELOW the moves (sort 50), for
            // a player who wants to study the hand rather than just its number.
            Text(verbatim: totalText(hand))
                .font(.system(size: 50, weight: .heavy, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundColor(state.activeHandIndex == index
                                 ? TablePalette.accent : TablePalette.primaryText)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(state.hasSplit ? "blackjack.hand.\(index)" : "blackjack.hand")
                .accessibilityLabel(Text(verbatim: BlackjackReadout.total(hand,
                                                                          index: index,
                                                                          handCount: state.hands.count)))
                .accessibilitySortPriority(90 - Double(index) * 2)
                // Where focus goes when the wager box vanishes (D-092): straight to the
                // total. Only the FIRST hand claims — a split must not yank the cursor
                // off a hand still being played.
                .voiceOverFocusClaim(index == 0)

            if let outcome = hand.outcome {
                Text(verbatim: BlackjackTableView.outcomeCaption(outcome))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(TablePalette.secondaryText)
                    .accessibilityHidden(true)
            }

            FittedCardRow(faces: hand.cards.map { .up($0) })
                .frame(minHeight: 40)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(state.hasSplit ? "blackjack.hand.\(index).cards" : "blackjack.hand.cards")
                .accessibilityLabel(Text(verbatim: BlackjackReadout.handCards(hand)))
                .accessibilitySortPriority(50 - Double(index) * 2)
        }
        .padding(.vertical, 2)
    }

    /// The visible total, WITHOUT the outcome — the outcome is its own line so the
    /// number can be large (D-100).
    private func totalText(_ hand: BlackjackHandPresentation) -> String {
        hand.isSoft ? uiLocalized("blackjack.total.soft", hand.total)
                    : uiLocalized("blackjack.total.hard", hand.total)
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
