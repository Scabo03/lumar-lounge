// ActionBarView.swift
// =====================================================================
// The action controls: the button bar (Check/Call, Fold, Raise), the Raise box
// (minus, value, plus, all-in + confirm/cancel), and the end-of-game overlay.
//
// Buttons are active only on the human's turn: otherwise they are dimmed AND
// disabled for VoiceOver (D-021). Visible text uses the normal English poker
// terms; VoiceOver labels use the phonetic Italian spelling (D-016). Every
// control has an accessibility identifier for the UI tests.

import SwiftUI
import GameEngine

// MARK: - Action bar

struct ActionBarView: View {
    @ObservedObject var model: TableViewModel

    var body: some View {
        let turn = model.humanTurn
        HStack(spacing: 10) {
            ActionButton(title: checkCallTitle(turn),
                         a11yLabel: checkCallLabel(turn),
                         identifier: "action.checkcall",
                         kind: .neutral,
                         enabled: turn != nil) { model.checkOrCall() }

            ActionButton(title: uiLocalized("action.fold"),
                         a11yLabel: uiLocalized("action.fold.a11y"),
                         identifier: "action.fold",
                         kind: .danger,
                         enabled: turn?.canFold ?? false) { model.fold() }

            ActionButton(title: uiLocalized("action.raise"),
                         // EAR-VERIFIED plain render "Raise" (D-060) — no IPA.
                         a11yLabel: uiLocalized("action.raise.a11y"),
                         identifier: "action.raise",
                         kind: .accent,
                         enabled: turn?.canBetOrRaise ?? false) { model.openRaiseBox() }
        }
        .padding(.vertical, 4)
        // No identifier on this container: the buttons (action.*) are the leaves.
    }

    private func checkCallTitle(_ turn: HumanTurnInfo?) -> String {
        guard let turn else { return uiLocalized("action.checkcall.idle") }
        return turn.canCheck ? uiLocalized("action.check") : uiLocalized("action.call", turn.callAmount)
    }

    private func checkCallLabel(_ turn: HumanTurnInfo?) -> String {
        guard let turn else { return uiLocalized("action.checkcall.idle.a11y") }   // phonetic (D-054)
        return turn.canCheck ? uiLocalized("action.check.a11y") : uiLocalized("action.call.a11y", turn.callAmount)
    }
}

// MARK: - Reusable buttons

private enum ButtonKind { case neutral, danger, accent }

private struct ActionButton: View {
    let title: String
    let a11yLabel: String
    let identifier: String
    let kind: ButtonKind
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.headline)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(enabled ? foreground : TablePalette.foldedDim)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(enabled ? background : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(enabled ? background.opacity(0.9) : Color.white.opacity(0.12),
                                      lineWidth: 1)
                )
        }
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(verbatim: a11yLabel))
    }

    private var background: Color {
        switch kind {
        case .neutral: return Color(red: 0.16, green: 0.36, blue: 0.52)
        case .danger: return Color(red: 0.52, green: 0.14, blue: 0.16)
        case .accent: return Color(red: 0.34, green: 0.30, blue: 0.10)
        }
    }
    private var foreground: Color { .white }
}

// MARK: - Raise box

struct RaiseBoxView: View {
    @ObservedObject var model: TableViewModel
    let box: RaiseBoxState

    var body: some View {
        VStack(spacing: 16) {
            Text(verbatim: box.isBet ? uiLocalized("raise.title.bet") : uiLocalized("raise.title.raise"))
                .font(.headline)
                .foregroundStyle(TablePalette.primaryText)
                // Hidden from VoiceOver: the adjustable value below already carries
                // the dialog name, so the reader isn't told "Rilancio" twice (D-027).
                .accessibilityHidden(true)

            HStack(spacing: 12) {
                // +/- are ordinary VoiceOver buttons (double-tap): each changes the
                // value and then announces the new amount (D-027). The value in the
                // middle is a readable element so swiping onto it also reads "N fiche".
                stepButton("−", identifier: "raise.minus",
                           a11yLabel: uiLocalized("raise.minus.a11y"),
                           enabled: !box.isAtMin) { model.raiseMinus() }

                Text(verbatim: "\(box.value)")
                    .font(.title.weight(.bold).monospacedDigit())
                    .foregroundStyle(TablePalette.accent)
                    .frame(minWidth: 90)
                    .accessibilityElement()
                    .accessibilityIdentifier("raise.value")
                    // PHONETIC label (D-049): "reis"/"bett", never the visible English
                    // "Raise"/"Bet" — Italian VoiceOver reads "Raise" as "Ace".
                    .accessibilityLabel(Text(verbatim: box.isBet ? uiLocalized("raise.title.bet.a11y") : uiLocalized("raise.title.raise.a11y")))
                    .accessibilityValue(Text(verbatim: uiLocalized("announce.raise.value", box.value)))
                    // Land VoiceOver on the adjustable amount when the box opens, so the
                    // reader immediately hears "reis, N fiche" instead of the now-hidden
                    // table behind it (D-027, via the shared focus-landing pattern D-057).
                    .voiceOverFocusLanding()

                stepButton("+", identifier: "raise.plus",
                           a11yLabel: uiLocalized("raise.plus.a11y"),
                           enabled: !box.isAtMax) { model.raisePlus() }

                stepButton(uiLocalized("raise.allin"), identifier: "raise.allin",
                           a11yLabel: uiLocalized("raise.allin.a11y"),
                           enabled: true, wide: true) { model.raiseAllIn() }
            }

            HStack(spacing: 12) {
                Button { model.cancelRaise() } label: {
                    Text(verbatim: uiLocalized("raise.cancel"))
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.14)))
                }
                .accessibilityIdentifier("raise.cancel")
                .accessibilityLabel(Text(verbatim: uiLocalized("raise.cancel.a11y")))

                Button { model.confirmRaise() } label: {
                    Text(verbatim: confirmTitle)
                        .font(.headline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.black)
                        .background(RoundedRectangle(cornerRadius: 12).fill(TablePalette.accent))
                }
                .accessibilityIdentifier("raise.confirm")
                .accessibilityLabel(Text(verbatim: confirmLabel))
            }
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.10, green: 0.12, blue: 0.15))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(TablePalette.accent, lineWidth: 2))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("raisebox")
    }

    private var confirmTitle: String {
        box.isAtMax ? uiLocalized("raise.allin") : uiLocalized("raise.confirm.to", box.value)
    }
    private var confirmLabel: String {
        box.isAtMax ? uiLocalized("raise.confirm.allin.a11y", box.value) : uiLocalized("raise.confirm.a11y", box.value)
    }

    private func stepButton(_ title: String, identifier: String, a11yLabel: String,
                            enabled: Bool, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.title2.weight(.bold))
                .frame(minWidth: wide ? 72 : 52, minHeight: 52)
                .foregroundStyle(enabled ? .white : TablePalette.foldedDim)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(enabled ? 0.16 : 0.05)))
        }
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(verbatim: a11yLabel))
    }
}

// MARK: - End of game overlay

struct EndOverlay: View {
    let outcome: GameOutcome
    let onReturn: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 24) {
                Text(verbatim: uiLocalized(outcome == .won ? "endgame.won" : "endgame.lost"))
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(TablePalette.primaryText)
                    .accessibilityIdentifier("endgame.message")
                    .accessibilityAddTraits(.isHeader)
                    .voiceOverFocusLanding()   // land VoiceOver on the outcome (D-057)

                Button(action: onReturn) {
                    Text(verbatim: uiLocalized("endgame.return"))
                        .font(.headline.weight(.bold))
                        .padding(.horizontal, 28).padding(.vertical, 14)
                        .foregroundStyle(.black)
                        .background(Capsule().fill(TablePalette.accent))
                }
                .accessibilityIdentifier("endgame.button")
            }
            .padding(36)
            .background(RoundedRectangle(cornerRadius: 20).fill(TablePalette.cardBack))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(TablePalette.accent, lineWidth: 2))
        }
    }
}
