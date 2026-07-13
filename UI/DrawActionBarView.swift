// DrawActionBarView.swift
// =====================================================================
// The Five-Card Draw betting bar: Fold, Check/Call, Bet, Raise — all LIMIT, so
// Bet/Raise carry a FIXED amount shown in the label ("Bet 20", "Raise 40"); there
// is no progressive raise box (D-044). Buttons are active only on the human's
// betting turn; otherwise dimmed AND disabled for VoiceOver (D-021).
//
// Opening is on the honour system (D-039): the Bet button stays active even when
// the human can't prove openers — responsibility only bites at showdown. Raise is
// disabled once the round's raise cap is reached (the engine reports canRaise=false).

import SwiftUI
import GameEngine

struct DrawActionBarView: View {
    @ObservedObject var model: DrawTableViewModel

    var body: some View {
        let turn = model.bettingTurn
        HStack(spacing: 8) {
            DrawActionButton(title: checkCallTitle(turn), a11yLabel: checkCallLabel(turn),
                             identifier: "action.checkcall", kind: .neutral,
                             enabled: turn != nil) { model.checkOrCall() }

            DrawActionButton(title: uiLocalized("action.fold"), a11yLabel: uiLocalized("action.fold.a11y"),
                             identifier: "action.fold", kind: .danger,
                             enabled: turn?.canFold ?? false) { model.fold() }

            DrawActionButton(title: betTitle(turn), a11yLabel: betLabel(turn),
                             identifier: "action.bet", kind: .accent,
                             enabled: turn?.canBet ?? false) { model.betOpen() }

            DrawActionButton(title: raiseTitle(turn), a11yLabel: raiseLabel(turn),
                             identifier: "action.raise", kind: .accent,
                             enabled: turn?.canRaise ?? false) { model.raise() }
        }
        .padding(.vertical, 4)
    }

    private func checkCallTitle(_ turn: DrawBettingTurn?) -> String {
        guard let turn else { return uiLocalized("action.checkcall.idle") }
        return turn.canCheck ? uiLocalized("action.check") : uiLocalized("action.call", turn.callAmount)
    }
    private func checkCallLabel(_ turn: DrawBettingTurn?) -> String {
        guard let turn else { return uiLocalized("action.checkcall.idle.a11y") }   // phonetic (D-054)
        return turn.canCheck ? uiLocalized("action.check.a11y") : uiLocalized("action.call.a11y", turn.callAmount)
    }
    private func betTitle(_ turn: DrawBettingTurn?) -> String {
        uiLocalized("draw.action.bet", turn?.betTo ?? 0)
    }
    private func betLabel(_ turn: DrawBettingTurn?) -> String {
        uiLocalized("draw.action.bet.a11y", turn?.betTo ?? 0)
    }
    private func raiseTitle(_ turn: DrawBettingTurn?) -> String {
        uiLocalized("draw.action.raise", turn?.raiseTo ?? 0)
    }
    private func raiseLabel(_ turn: DrawBettingTurn?) -> String {
        uiLocalized("draw.action.raise.a11y", turn?.raiseTo ?? 0)
    }
}

private enum DrawButtonKind { case neutral, danger, accent }

private struct DrawActionButton: View {
    let title: String
    let a11yLabel: String
    let identifier: String
    let kind: DrawButtonKind
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.subheadline.weight(.semibold)).minimumScaleFactor(0.5).lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(enabled ? Color.white : TablePalette.foldedDim)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(enabled ? background : Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(enabled ? background.opacity(0.9) : Color.white.opacity(0.12), lineWidth: 1))
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
}
