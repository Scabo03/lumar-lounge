// BlackjackActionBarView.swift
// =====================================================================
// The five moves, and the wager box.
//
// On the button labels: the visible titles keep the English terms the game is
// played in, as everywhere else in the project, while the VoiceOver label is
// the ITALIAN word. That is deliberate and provisional (D-090). The Italian
// words — carta, stai, raddoppia, dividi, resa — are real words in the
// language the voice speaks, so they are correct BY CONSTRUCTION and cannot
// mispronounce the way an invented English-ish spelling did for three
// sessions with "raise" (D-049/D-054/D-059/D-060). Ear samples of both the
// English and the Italian candidates are waiting for the user's verdict; if
// English is preferred, only these `.a11y` strings change.

import SwiftUI
import GameEngine
import GameWorld

private enum BlackjackButtonKind { case neutral, danger, accent, quiet }

private struct BlackjackActionButton: View {
    let title: String
    let a11yLabel: String
    let identifier: String
    let kind: BlackjackButtonKind
    let enabled: Bool
    let action: () -> Void

    private var background: Color {
        switch kind {
        case .neutral: return Color.white.opacity(0.12)
        case .danger:  return Color(red: 0.45, green: 0.13, blue: 0.13)
        case .accent:  return Color(red: 0.16, green: 0.38, blue: 0.24)
        case .quiet:   return Color.white.opacity(0.07)
        }
    }

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundColor(enabled ? TablePalette.primaryText : TablePalette.foldedDim)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(background.opacity(enabled ? 1 : 0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(verbatim: a11yLabel))
    }
}

struct BlackjackActionBarView: View {
    @ObservedObject var model: BlackjackTableViewModel

    private var turn: BlackjackTurnContext? { model.turn }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                BlackjackActionButton(title: uiLocalized("blackjack.action.hit"),
                                      a11yLabel: uiLocalized("blackjack.action.hit.a11y"),
                                      identifier: "action.hit", kind: .accent,
                                      enabled: turn?.legal.canHit ?? false) { model.hit() }

                BlackjackActionButton(title: uiLocalized("blackjack.action.stand"),
                                      a11yLabel: uiLocalized("blackjack.action.stand.a11y"),
                                      identifier: "action.stand", kind: .neutral,
                                      enabled: turn?.legal.canStand ?? false) { model.stand() }
            }

            HStack(spacing: 8) {
                BlackjackActionButton(title: uiLocalized("blackjack.action.double"),
                                      a11yLabel: uiLocalized("blackjack.action.double.a11y"),
                                      identifier: "action.double", kind: .quiet,
                                      enabled: turn?.legal.canDouble ?? false) { model.double() }

                BlackjackActionButton(title: uiLocalized("blackjack.action.split"),
                                      a11yLabel: uiLocalized("blackjack.action.split.a11y"),
                                      identifier: "action.split", kind: .quiet,
                                      enabled: turn?.legal.canSplit ?? false) { model.split() }

                BlackjackActionButton(title: uiLocalized("blackjack.action.surrender"),
                                      a11yLabel: uiLocalized("blackjack.action.surrender.a11y"),
                                      identifier: "action.surrender", kind: .danger,
                                      enabled: turn?.legal.canSurrender ?? false) { model.surrender() }
            }
        }
    }
}

// MARK: - The wager box

struct BlackjackBetBoxView: View {
    @ObservedObject var model: BlackjackTableViewModel
    let box: BlackjackBetBox

    var body: some View {
        VStack(spacing: 14) {
            Text(verbatim: uiLocalized("blackjack.bet.title"))
                .font(.title3.weight(.semibold))
                .foregroundColor(TablePalette.primaryText)
                .accessibilityHidden(true)

            Text(verbatim: uiLocalized("blackjack.bet.display", box.value))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(TablePalette.accent)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("bet.value")
                .accessibilityLabel(Text(verbatim: uiLocalized("blackjack.bet.title")))
                .accessibilityValue(Text(verbatim: uiLocalized("blackjack.bet.value.a11y", box.value)))
                .voiceOverFocusLanding()

            HStack(spacing: 10) {
                stepButton("−", identifier: "bet.minus",
                           a11yLabel: uiLocalized("blackjack.bet.minus.a11y"),
                           enabled: !box.isAtMin) { model.betMinus() }

                stepButton("+", identifier: "bet.plus",
                           a11yLabel: uiLocalized("blackjack.bet.plus.a11y"),
                           enabled: !box.isAtMax) { model.betPlus() }

                stepButton(uiLocalized("blackjack.bet.max"), identifier: "bet.max",
                           a11yLabel: uiLocalized("blackjack.bet.max.a11y"),
                           enabled: !box.isAtMax, wide: true) { model.betMax() }
            }

            Button(action: { model.confirmBet() }) {
                Text(verbatim: uiLocalized("blackjack.bet.confirm"))
                    .font(.headline)
                    .foregroundColor(TablePalette.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(red: 0.16, green: 0.38, blue: 0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityIdentifier("bet.confirm")
            .accessibilityLabel(Text(verbatim: uiLocalized("blackjack.bet.confirm.a11y", box.value)))
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(Color(red: 0.10, green: 0.12, blue: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(TablePalette.accent.opacity(0.5), lineWidth: 1))
        .accessibilityIdentifier("betbox")
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ title: String,
                            identifier: String,
                            a11yLabel: String,
                            enabled: Bool,
                            wide: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.title3.weight(.semibold))
                .foregroundColor(enabled ? TablePalette.primaryText : TablePalette.foldedDim)
                .frame(maxWidth: wide ? .infinity : 64, minHeight: 46)
                .background(Color.white.opacity(enabled ? 0.12 : 0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(verbatim: a11yLabel))
    }
}
