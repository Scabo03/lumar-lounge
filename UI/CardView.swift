// CardView.swift
// =====================================================================
// One playing card, face-up or face-down. Sizes scale with Dynamic Type via
// `@ScaledMetric` so the whole card grows with the user's text-size preference.
// Face-up cards read their spoken (Italian) name to VoiceOver; face-down cards
// read as "covered card" — spectators never learn a hole card's value.

import SwiftUI
import GameEngine

struct CardView: View {
    enum Face: Equatable {
        case up(Card)
        case down
    }

    /// The rendered size. `medium` suits the five hero cards of Five-Card Draw,
    /// where two big cards' worth of width must hold five (D-044).
    enum Size: Equatable {
        case normal, medium, big, huge
        /// An EXACT, NON-Dynamic-Type-scaled size (D-089). Used where the caller has
        /// already sized the card to the space it must fit into — re-scaling it there
        /// would defeat the fitting and push the row off screen again.
        case exact(CGFloat, CGFloat)
    }

    let face: Face
    private let size: Size

    @ScaledMetric private var scaledWidth: CGFloat
    @ScaledMetric private var scaledHeight: CGFloat
    /// Set only for `.exact`, which opts OUT of Dynamic Type scaling (D-089).
    private let fixed: CGSize?

    private var width: CGFloat { fixed?.width ?? scaledWidth }
    private var height: CGFloat { fixed?.height ?? scaledHeight }

    /// - Parameter big: a large variant for the human's own hole cards (Texas).
    init(face: Face, big: Bool = false) {
        self.init(face: face, size: big ? .big : .normal)
    }

    /// Explicit-size initializer (used by the draw table's five-card layouts).
    init(face: Face, size: Size) {
        self.face = face
        self.size = size
        let w: CGFloat, h: CGFloat
        switch size {
        case .normal: (w, h) = (40, 56)
        case .medium: (w, h) = (52, 74)
        case .big:    (w, h) = (78, 108)
        case .huge:   (w, h) = (64, 92)
        case let .exact(ew, eh): (w, h) = (ew, eh)
        }
        if case .exact = size { fixed = CGSize(width: w, height: h) } else { fixed = nil }
        _scaledWidth = ScaledMetric(wrappedValue: w, relativeTo: .title3)
        _scaledHeight = ScaledMetric(wrappedValue: h, relativeTo: .title3)
    }

    private var big: Bool { size == .big || size == .huge }

    /// Below this width the rank glyph needs the smaller font to stay legible.
    private var tiny: Bool { (fixed?.width ?? 40) < 34 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fillColor)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
            if case let .up(card) = face {
                Text(CardText.symbol(card))
                    .font((big ? Font.largeTitle : (tiny ? Font.footnote : Font.title3)).weight(.bold))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(TablePalette.suitColor(card.suit))
                    .padding(2)
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                    .padding(5)
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    private var fillColor: Color {
        switch face {
        case .up: return TablePalette.cardFace
        case .down: return TablePalette.cardBack
        }
    }

    private var accessibilityText: String {
        switch face {
        case let .up(card): return CardText.spoken(card)
        case .down: return uiLocalized("card.a11y.covered")
        }
    }
}
