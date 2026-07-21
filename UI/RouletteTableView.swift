// RouletteTableView.swift
// =====================================================================
// The roulette table (D-103), in three zones on one `RouletteBetSlip`.
//
// ZONE 1 — the SELECTION TABLE: every offered bet as a cell. Its VoiceOver order
// follows FREQUENCY, not the felt's geometry (sort priorities from the model's
// frequency rank): red/black/even/odd → the halves → dozens & columns → the
// multi-number inside bets → the single numbers. Each cell is an ADJUSTABLE
// element — swipe up/down changes the fiches on it, double-tap places the
// minimum — and its value is read where the swipe happens, so the state is
// legible as the player crosses it.
//
// ZONE 2 — the REGISTER BAND (bottom-left): a compact, operable view of the
// sparse bet state — the total, plus a symbol per active bet whose VoiceOver
// label says what it is and how much is on it. Each symbol is ITSELF adjustable
// (swipe to zero removes), acting on the SAME slip through the SAME methods as
// the table (D-102): two interfaces, never two implementations.
//
// ZONE 3 — CONFIRM, bottom-right at the very edge so the thumb finds it, and it
// declares the total risked.
//
// SUBTREE STABILITY (D-052): the table's cells are a FIXED set (every bet always
// has a cell; only its value changes), so composing never restructures the grid
// and VoiceOver never re-lands. The band's symbols come and go with the bets, so
// removing the focused symbol hands focus to the band total (D-092).

import SwiftUI
import GameEngine
import GameWorld
import Audio

struct RouletteTableScreen: View {
    @StateObject private var model: RouletteTableViewModel

    init(rules: RouletteTableRules, audio: AudioEngine, mode: AppVoiceOverMode,
         returnLabel: String = uiLocalized("endgame.return"),
         casinoAudio: CasinoAudio = .riverwood, onLeave: @escaping (Int) -> Void) {
        let fastMode = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        _model = StateObject(wrappedValue: RouletteTableViewModel(
            fastMode: fastMode, audio: audio, mode: mode, rules: rules,
            returnLabel: returnLabel, casinoAudio: casinoAudio, onLeave: onLeave))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                topBar
                RouletteFeltView(model: model)
                RouletteBettingSurface(model: model)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.top, 6)
            .accessibilityHidden(model.outcome != nil)

            // The register band (left) and the confirm button (right), pinned to the
            // very bottom — confirm at the trailing edge for the thumb.
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 8) {
                    RouletteRegisterBand(model: model)
                    Spacer(minLength: 6)
                    RouletteConfirmButton(model: model)
                }
                .padding(.horizontal, 10).padding(.bottom, 6)
            }
            .accessibilityHidden(model.outcome != nil)

            if let outcome = model.outcome {
                EndOverlay(outcome: outcome, onReturn: { model.returnToCasino() },
                           returnLabel: model.returnLabel)
            }
        }
        .task { await model.run() }
    }

    private var topBar: some View {
        HStack {
            Button(action: { model.requestLeave() }) {
                Text(verbatim: uiLocalized("roulette.leave"))
                    .font(.subheadline).foregroundColor(TablePalette.secondaryText)
            }
            .accessibilityIdentifier("roulette.leave")
            .accessibilityHint(Text(verbatim: uiLocalized("roulette.leave.hint")))
            .accessibilitySortPriority(1)
            Spacer()
        }
    }
}

// MARK: - The felt: the central status / result element (focus anchor)

private struct RouletteFeltView: View {
    @ObservedObject var model: RouletteTableViewModel

    var body: some View {
        VStack(spacing: 4) {
            // The big number wheel-face: dash while betting/spinning, the result after.
            Text(verbatim: pocketText)
                .font(.system(size: 54, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundColor(pocketColor)
                .accessibilityHidden(true)
            Text(verbatim: captionText)
                .font(.subheadline).foregroundColor(TablePalette.secondaryText)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.35)))
        // One STABLE leaf whose LABEL changes with the phase — the focus anchor after
        // confirm and after the outcome (D-092), and the interrogable total while betting.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("roulette.felt")
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .accessibilitySortPriority(1000)
        .voiceOverFocusLanding()
        .voiceOverFocusClaim(onChangeOf: model.focusToken)
    }

    private var pocketText: String {
        switch model.state.phase {
        case .resolved: return "\(model.state.lastPocket ?? 0)"
        default:        return "—"
        }
    }
    private var pocketColor: Color {
        guard model.state.phase == .resolved, let c = model.state.lastColor else { return TablePalette.secondaryText }
        switch c {
        case .red: return Color(red: 0.8, green: 0.16, blue: 0.16)
        case .black: return TablePalette.primaryText
        case .green: return TablePalette.accent
        }
    }
    private var captionText: String {
        switch model.state.phase {
        case .betting: return uiLocalized("roulette.status.title")
        case .spinning: return uiLocalized("roulette.status.spinning")
        case .resolved, .ended: return ""
        }
    }
    private var a11yLabel: String {
        switch model.state.phase {
        case .betting:
            return model.slip.totalStaked > 0
                ? uiLocalized("roulette.status.betting", model.slip.totalStaked)
                : uiLocalized("roulette.status.betting.none")
        case .spinning:
            return uiLocalized("roulette.status.spinning")
        case .resolved, .ended:
            guard let r = model.state.lastResolution else { return uiLocalized("roulette.status.title") }
            return RouletteSpeechMap.outcomeLine(for: r)
        }
    }
}

// MARK: - Zone 1: the betting surface (frequency-ordered cells)

private struct RouletteBettingSurface: View {
    @ObservedObject var model: RouletteTableViewModel

    /// A global order index per bet, so sort priorities descend in frequency order.
    private static let order: [RouletteBet: Int] = {
        var map: [RouletteBet: Int] = [:]
        for (i, bet) in RouletteBoard.allBets.enumerated() { map[bet] = i }
        return map
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(RouletteBoard.groups, id: \.id) { group in
                    section(group)
                }
            }
            .padding(.bottom, 96)   // room above the pinned band / confirm
        }
    }

    @ViewBuilder private func section(_ group: RouletteBoard.Group) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: uiLocalized("roulette.group.\(group.id)"))
                .font(.caption.weight(.semibold)).foregroundColor(TablePalette.accent)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns(for: group), alignment: .leading, spacing: 5) {
                ForEach(group.bets, id: \.self) { bet in
                    RouletteBetCell(model: model, bet: bet,
                                    sortPriority: 900 - Double(Self.order[bet] ?? 0))
                }
            }
        }
    }

    private func columns(for group: RouletteBoard.Group) -> [GridItem] {
        switch group.id {
        case "numbers": return Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
        case "inside":  return [GridItem(.flexible())]   // a readable list
        default:        return Array(repeating: GridItem(.flexible(), spacing: 5), count: 2)
        }
    }
}

/// One bet cell — a STABLE adjustable leaf. Its subtree never changes shape; only its
/// label/value do, so VoiceOver never re-lands while the player composes (D-052).
private struct RouletteBetCell: View {
    @ObservedObject var model: RouletteTableViewModel
    let bet: RouletteBet
    let sortPriority: Double

    private var amount: Int { model.slip.amount(on: bet) }

    var body: some View {
        let placed = amount > 0
        return Text(verbatim: RouletteSpeechMap.betName(bet) + (placed ? "\n\(amount)" : ""))
            .font(.footnote.weight(placed ? .bold : .regular))
            .multilineTextAlignment(.center)
            .lineLimit(2).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 4).padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 8).fill(cellColor(placed: placed)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(TablePalette.accent, lineWidth: placed ? 2 : 0))
            .contentShape(Rectangle())
            .onTapGesture { model.tapCell(bet) }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("roulette.cell.\(bet.kind.rawValue).\(bet.covered.map(String.init).joined(separator: "-"))")
            .accessibilityLabel(Text(verbatim: RouletteSpeechMap.betName(bet)))
            .accessibilityValue(Text(verbatim: valueText(placed: placed)))
            .accessibilityHint(Text(verbatim: uiLocalized("roulette.cell.hint")))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.increase(bet)
                case .decrement: model.decrease(bet)
                @unknown default: break
                }
            }
            .accessibilityAction { model.placeMinimum(bet) }
            .accessibilitySortPriority(sortPriority)
    }

    private func valueText(placed: Bool) -> String {
        placed ? uiLocalized("roulette.cell.a11y", RouletteSpeechMap.betName(bet), amount)
               : uiLocalized("roulette.cell.a11y.empty", RouletteSpeechMap.betName(bet))
    }

    private func cellColor(placed: Bool) -> Color {
        switch RouletteLayout.color(of: bet.covered.first ?? -1) {
        case .red where bet.kind == .straight:   return Color(red: 0.55, green: 0.12, blue: 0.12)
        case .black where bet.kind == .straight: return Color.black.opacity(0.55)
        case .green where bet.kind == .straight: return Color(red: 0.12, green: 0.35, blue: 0.2)
        default: return Color.white.opacity(placed ? 0.18 : 0.08)
        }
    }
}

// MARK: - Zone 2: the register band

private struct RouletteRegisterBand: View {
    @ObservedObject var model: RouletteTableViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The total — ALWAYS interrogable before confirming (D-102). Also the focus
            // target when a symbol is removed under the cursor.
            Text(verbatim: "\(uiLocalized("roulette.register.title")): \(model.slip.totalStaked)")
                .font(.caption.weight(.bold)).foregroundColor(TablePalette.primaryText)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("roulette.register.total")
                .accessibilityLabel(Text(verbatim: uiLocalized("roulette.register.total.a11y", model.slip.totalStaked)))
                .accessibilitySortPriority(700)
                .voiceOverFocusClaim(onChangeOf: model.slip.bets.count)

            if model.slip.bets.isEmpty {
                Text(verbatim: uiLocalized("roulette.register.empty"))
                    .font(.caption2).foregroundColor(TablePalette.secondaryText)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("roulette.register.empty")
                    .accessibilityLabel(Text(verbatim: uiLocalized("roulette.register.empty.a11y")))
                    .accessibilitySortPriority(690)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(model.slip.orderedBets, id: \.bet) { entry in
                            RouletteSymbol(model: model, bet: entry.bet, amount: entry.amount)
                        }
                    }
                }
                .frame(maxWidth: 210)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.4)))
    }
}

/// A compact, operable symbol for one active bet — adjustable on the SAME slip (D-102).
private struct RouletteSymbol: View {
    @ObservedObject var model: RouletteTableViewModel
    let bet: RouletteBet
    let amount: Int

    var body: some View {
        VStack(spacing: 1) {
            Text(verbatim: shortName)
                .font(.caption2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(verbatim: "\(amount)")
                .font(.caption2).foregroundColor(TablePalette.accent)
        }
        .frame(minWidth: 42, minHeight: 40)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(TablePalette.accent.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("roulette.symbol.\(bet.kind.rawValue).\(bet.covered.map(String.init).joined(separator: "-"))")
        .accessibilityLabel(Text(verbatim: RouletteSpeechMap.betName(bet)))
        .accessibilityValue(Text(verbatim: uiLocalized("roulette.cell.a11y", RouletteSpeechMap.betName(bet), amount)))
        .accessibilityHint(Text(verbatim: uiLocalized("roulette.symbol.hint")))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.increase(bet)
            case .decrement: model.decrease(bet)   // to zero → removed; focus goes to the total
            @unknown default: break
            }
        }
        .accessibilitySortPriority(690)
    }

    private var shortName: String {
        // A terse tag for the sighted; the full name is in the VoiceOver label.
        switch bet.kind {
        case .red: return "R"; case .black: return "N"; case .even: return "P"; case .odd: return "D"
        case .low: return "M"; case .high: return "P2"
        case .straight: return "\(bet.covered.first ?? 0)"
        default: return RouletteSpeechMap.betName(bet).prefix(3).uppercased()
        }
    }
}

// MARK: - Zone 3: confirm

private struct RouletteConfirmButton: View {
    @ObservedObject var model: RouletteTableViewModel

    var body: some View {
        Button(action: { model.confirm() }) {
            Text(verbatim: uiLocalized("roulette.confirm"))
                .font(.headline.weight(.bold))
                .foregroundColor(model.canConfirm ? .black : TablePalette.foldedDim)
                .frame(width: 96, height: 56)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(model.canConfirm ? TablePalette.accent : Color.white.opacity(0.1)))
        }
        .disabled(!model.canConfirm)
        .accessibilityIdentifier("roulette.confirm")
        .accessibilityLabel(Text(verbatim: model.canConfirm
            ? uiLocalized("roulette.confirm.a11y", model.slip.totalStaked)
            : uiLocalized("roulette.confirm.a11y.none")))
        .accessibilitySortPriority(500)
    }
}
