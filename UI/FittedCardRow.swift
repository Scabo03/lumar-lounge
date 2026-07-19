// FittedCardRow.swift
// =====================================================================
// A row of cards that ALWAYS fits the width it is given (D-089).
//
// Seven-Card Stud is the first game here whose card count GROWS through the hand:
// by sixth street each opponent shows four up cards and the player holds seven. A
// row of fixed-size cards therefore cannot fit a phone — measured, the opponent
// band reached 544 pt against 369 pt of usable width, overflowing from FOURTH
// street onward. So the size must follow the space, not the other way round.
//
// Implemented with `ViewThatFits`, which picks the first candidate row that fits:
// no manual geometry maths, and it adapts to the device width AND to Dynamic Type
// for free — at an accessibility text size the larger candidates simply stop
// fitting and a smaller one is chosen, instead of the row running off screen.
//
// ACCESSIBILITY: this view is always used INSIDE a collapsed accessibility element
// (the opponent board, the hero's hand), so nothing here is navigated directly and
// the candidate swap never disturbs the accessibility tree — the element stays one
// stable leaf whose LABEL changes, which is the pattern D-046/D-083 prescribe.

import SwiftUI
import GameEngine

struct FittedCardRow: View {
    let faces: [CardView.Face]
    var spacing: CGFloat = 3
    /// Candidate widths, largest first — the first that fits the offered space wins.
    var candidates: [CGFloat] = [44, 40, 36, 32, 28, 24, 22]
    /// Card aspect ratio, matching the fixed CardView sizes (40×56).
    private let aspect: CGFloat = 56.0 / 40.0

    /// Dynamic Type must NOT be lost here (D-089). `.exact` opts out of scaling, so if
    /// the candidates were plain constants a low-vision player's cards would stop
    /// growing with their text size — a real regression. Instead the candidates are
    /// SCALED, so with room to spare the cards do grow; and an unscaled floor is
    /// appended last, so when even the smallest scaled size would not fit, the row
    /// still fits rather than running off screen. Dynamic Type is honoured up to the
    /// point where honouring it would push the hand out of sight, and staying on
    /// screen wins there — the same trade D-056 makes for pacing.
    @ScaledMetric(relativeTo: .title3) private var scale: CGFloat = 1

    /// The legibility floor for low-vision players: below ~20 pt the rank glyph stops
    /// being readable, so we would rather clip than go smaller.
    private static let absoluteFloor: CGFloat = 20

    private var sizes: [CGFloat] {
        candidates.map { $0 * scale } + candidates.filter { $0 <= 32 } + [Self.absoluteFloor]
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(sizes.enumerated()), id: \.offset) { _, width in
                row(cardWidth: width)
            }
        }
    }

    private func row(cardWidth: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(Array(faces.enumerated()), id: \.offset) { _, face in
                CardView(face: face, size: .exact(cardWidth, cardWidth * aspect))
            }
        }
    }
}
