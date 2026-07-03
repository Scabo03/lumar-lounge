// TablePalette.swift
// =====================================================================
// A small, high-contrast palette for the minimalist demo table. Defined in
// code (no asset catalog) so the whole look ships inside the UI module. High
// contrast serves low-vision users who don't use VoiceOver but need strong
// legibility (D-019). No rich casino theming yet — clarity first.

import SwiftUI
import GameEngine

enum TablePalette {
    static let background = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let felt = Color(red: 0.07, green: 0.24, blue: 0.19)
    static let feltEdge = Color.white.opacity(0.85)
    static let primaryText = Color.white
    static let secondaryText = Color(red: 0.82, green: 0.85, blue: 0.88)
    static let accent = Color(red: 0.97, green: 0.80, blue: 0.24) // gold: button, pot
    static let cardFace = Color(red: 0.97, green: 0.97, blue: 0.94)
    static let cardBack = Color(red: 0.55, green: 0.10, blue: 0.16) // bordeaux
    static let redSuit = Color(red: 0.72, green: 0.06, blue: 0.10)
    static let blackSuit = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let foldedDim = Color.white.opacity(0.35)

    static func suitColor(_ suit: Suit) -> Color {
        switch suit {
        case .hearts, .diamonds: return redSuit
        case .spades, .clubs: return blackSuit
        }
    }
}
