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

    let face: Face
    private let big: Bool

    @ScaledMetric private var width: CGFloat
    @ScaledMetric private var height: CGFloat

    /// - Parameter big: a large variant for the human's own hole cards.
    init(face: Face, big: Bool = false) {
        self.face = face
        self.big = big
        _width = ScaledMetric(wrappedValue: big ? 78 : 40, relativeTo: .title3)
        _height = ScaledMetric(wrappedValue: big ? 108 : 56, relativeTo: .title3)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fillColor)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
            if case let .up(card) = face {
                Text(CardText.symbol(card))
                    .font((big ? Font.largeTitle : Font.title3).weight(.bold))
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
