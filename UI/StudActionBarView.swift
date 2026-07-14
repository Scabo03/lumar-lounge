// StudActionBarView.swift
// =====================================================================
// The ClockTower Stud Pot Limit betting bar and its raise box (D-077). Check/Call, Fold,
// Raise — the same shape as Omaha — with a POT-LIMIT-aware raise box: its maximum is the
// pot-limit cap the engine reports, which can be BELOW the stack. When the stack exceeds
// the pot there is NO all-in shove: the max button reads "Pot" (not "All-in"), a caption
// shows the cap, and the VoiceOver cue says so (reuses the Omaha box behaviour, D-066).
//
// Buttons are active only on the human's turn; otherwise dimmed AND disabled for
// VoiceOver (D-021). Visible text uses the normal English terms; VoiceOver labels use the
// ear-verified phonetic renders (D-060). The palette is the ClockTower's bronze/parchment.

import SwiftUI
import GameEngine

/// The ClockTower's warm bronze look for the Stud table.
enum ClockPalette {
    static let felt = Color(red: 0.11, green: 0.09, blue: 0.07)       // dark walnut felt
    static let feltEdge = Color(red: 0.72, green: 0.56, blue: 0.30)   // weathered bronze
    static let accent = Color(red: 0.82, green: 0.64, blue: 0.36)     // bronze / gilt
}

struct StudActionBarView: View {
    @ObservedObject var model: StudTableViewModel

    var body: some View {
        let turn = model.humanTurn
        HStack(spacing: 10) {
            StudActionButton(title: checkCallTitle(turn), a11yLabel: checkCallLabel(turn),
                             identifier: "action.checkcall", kind: .neutral,
                             enabled: turn != nil) { model.checkOrCall() }

            StudActionButton(title: uiLocalized("action.fold"), a11yLabel: uiLocalized("action.fold.a11y"),
                             identifier: "action.fold", kind: .danger,
                             enabled: turn?.canFold ?? false) { model.fold() }

            StudActionButton(title: uiLocalized("action.raise"), a11yLabel: uiLocalized("action.raise.a11y"),
                             identifier: "action.raise", kind: .accent,
                             enabled: turn?.canBetOrRaise ?? false) { model.openRaiseBox() }
        }
        .padding(.vertical, 4)
    }

    private func checkCallTitle(_ turn: StudTurnInfo?) -> String {
        guard let turn else { return uiLocalized("action.checkcall.idle") }
        return turn.canCheck ? uiLocalized("action.check") : uiLocalized("action.call", turn.callAmount)
    }
    private func checkCallLabel(_ turn: StudTurnInfo?) -> String {
        guard let turn else { return uiLocalized("action.checkcall.idle.a11y") }
        return turn.canCheck ? uiLocalized("action.check.a11y") : uiLocalized("action.call.a11y", turn.callAmount)
    }
}

private enum StudButtonKind { case neutral, danger, accent }

private struct StudActionButton: View {
    let title: String
    let a11yLabel: String
    let identifier: String
    let kind: StudButtonKind
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.headline).minimumScaleFactor(0.6).lineLimit(1)
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
        case .neutral: return Color(red: 0.30, green: 0.24, blue: 0.14)
        case .danger: return Color(red: 0.42, green: 0.16, blue: 0.14)
        case .accent: return Color(red: 0.44, green: 0.33, blue: 0.16)
        }
    }
}

// MARK: - Pot Limit raise box

struct StudRaiseBoxView: View {
    @ObservedObject var model: StudTableViewModel
    let box: RaiseBoxState

    private var canShove: Bool { model.raiseCanShove }

    var body: some View {
        VStack(spacing: 14) {
            Text(verbatim: box.isBet ? uiLocalized("raise.title.bet") : uiLocalized("raise.title.raise"))
                .font(.headline).foregroundStyle(TablePalette.primaryText)
                .accessibilityHidden(true)

            HStack(spacing: 12) {
                stepButton("−", identifier: "raise.minus", a11yLabel: uiLocalized("raise.minus.a11y"),
                           enabled: !box.isAtMin) { model.raiseMinus() }

                Text(verbatim: "\(box.value)")
                    .font(.title.weight(.bold).monospacedDigit())
                    .foregroundStyle(ClockPalette.accent)
                    .frame(minWidth: 90)
                    .accessibilityElement()
                    .accessibilityIdentifier("raise.value")
                    .accessibilityLabel(Text(verbatim: box.isBet ? uiLocalized("raise.title.bet.a11y") : uiLocalized("raise.title.raise.a11y")))
                    .accessibilityValue(Text(verbatim: uiLocalized("omaha.raise.value.a11y", box.value)))
                    .voiceOverFocusLanding()   // land VoiceOver on the amount on open (D-027/D-057)

                stepButton("+", identifier: "raise.plus", a11yLabel: uiLocalized("raise.plus.a11y"),
                           enabled: !box.isAtMax) { model.raisePlus() }

                stepButton(canShove ? uiLocalized("raise.allin") : uiLocalized("omaha.raise.max.pot"),
                           identifier: "raise.allin",
                           a11yLabel: canShove ? uiLocalized("raise.allin.a11y") : uiLocalized("omaha.raise.max.pot.a11y"),
                           enabled: true, wide: true) { model.raiseMax() }
            }

            if !canShove {
                Text(verbatim: uiLocalized("omaha.raise.cap.caption", model.raiseCapTo))
                    .font(.caption.weight(.semibold)).foregroundStyle(TablePalette.secondaryText)
                    .accessibilityIdentifier("raise.cap")
                    .accessibilityLabel(Text(verbatim: uiLocalized("omaha.raise.cap.a11y", model.raiseCapTo)))
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
                        .background(RoundedRectangle(cornerRadius: 12).fill(ClockPalette.accent))
                }
                .accessibilityIdentifier("raise.confirm")
                .accessibilityLabel(Text(verbatim: confirmLabel))
            }
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.12, green: 0.10, blue: 0.07))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(ClockPalette.accent, lineWidth: 2)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("raisebox")
    }

    private var confirmTitle: String {
        guard box.isAtMax else { return uiLocalized("raise.confirm.to", box.value) }
        return canShove ? uiLocalized("raise.allin") : uiLocalized("omaha.raise.max.pot")
    }
    private var confirmLabel: String {
        guard box.isAtMax else { return uiLocalized("raise.confirm.a11y", box.value) }
        return canShove ? uiLocalized("raise.confirm.allin.a11y", box.value) : uiLocalized("omaha.raise.cap.a11y", box.value)
    }

    private func stepButton(_ title: String, identifier: String, a11yLabel: String,
                            enabled: Bool, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.title2.weight(.bold)).minimumScaleFactor(0.5).lineLimit(1)
                .frame(minWidth: wide ? 72 : 52, minHeight: 52)
                .foregroundStyle(enabled ? .white : TablePalette.foldedDim)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(enabled ? 0.16 : 0.05)))
        }
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(verbatim: a11yLabel))
    }
}
