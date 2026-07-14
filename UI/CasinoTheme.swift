// CasinoTheme.swift
// =====================================================================
// A casino's visual identity (D-066): the palette + typography that make each place
// feel like a DIFFERENT PLACE, not a richer version of the last. The Riverwood is
// dark wood, deep-green felt, matte brass and a classic serif — rustic frontier
// warmth. The Skypool is its opposite: stone, marble, water, cool urban blue-greys
// and a modern, austere sans face.
//
// The theme drives the lobby screens and the chrome backdrop around a casino's
// tables, so entering a casino changes the whole surround. The poker felt itself
// stays green (a shared game surface) except the Skypool's speciality "Marble" table,
// which gets a cool marble centre as its signature (see OmahaTableView). UI only.

import SwiftUI
import GameWorld

struct CasinoTheme {
    /// The full-screen backdrop behind the chrome and content.
    let background: Color
    /// A panel/card fill (table rows, casino cards).
    let panel: Color
    /// A panel border tint.
    let panelEdge: Color
    /// The accent (headings, chevrons, highlights).
    let accent: Color
    let primaryText: Color
    let secondaryText: Color
    /// The typographic design for headings — serif at the Riverwood, a plain modern
    /// face at the Skypool.
    let titleDesign: Font.Design

    /// The Riverwood look — identical to the pre-generalisation palette (D-065): warm,
    /// dark, green felt, brass gold, serif.
    static let riverwood = CasinoTheme(
        background: Color(red: 0.05, green: 0.06, blue: 0.08),
        panel: Color(red: 0.07, green: 0.24, blue: 0.19),          // green felt
        panelEdge: Color(red: 0.97, green: 0.80, blue: 0.24),      // brass
        accent: Color(red: 0.97, green: 0.80, blue: 0.24),
        primaryText: .white,
        secondaryText: Color(red: 0.82, green: 0.85, blue: 0.88),
        titleDesign: .serif)

    /// The Skypool look (D-066): cool urban stone — slate backdrop, marble-grey panels,
    /// a steel/cyan accent, a clean modern (default) face. Austere, cold, city.
    static let skypool = CasinoTheme(
        background: Color(red: 0.06, green: 0.09, blue: 0.13),     // deep slate
        panel: Color(red: 0.14, green: 0.19, blue: 0.25),         // marble grey-blue
        panelEdge: Color(red: 0.55, green: 0.78, blue: 0.90),     // pale steel/water
        accent: Color(red: 0.55, green: 0.82, blue: 0.95),        // cool cyan/water
        primaryText: .white,
        secondaryText: Color(red: 0.78, green: 0.84, blue: 0.90),
        titleDesign: .default)

    /// The ClockTower look (D-072): an ancient, exclusive, ACADEMIC tower — aged stone,
    /// noble walnut, parchment, weathered bronze and ink. Erudite and refined, a third
    /// AXIS (not a step above the Skypool): Riverwood is the frontier, Skypool the money,
    /// ClockTower the PRESTIGE. Warm scholarly darks + bronze + parchment, serif — deep
    /// enough to read distinct from the Riverwood's green felt and bright brass.
    static let clockTower = CasinoTheme(
        background: Color(red: 0.07, green: 0.06, blue: 0.05),     // dark walnut/ink
        panel: Color(red: 0.16, green: 0.12, blue: 0.09),         // aged wood
        panelEdge: Color(red: 0.72, green: 0.56, blue: 0.30),     // weathered bronze
        accent: Color(red: 0.80, green: 0.62, blue: 0.34),        // bronze / gilt
        primaryText: Color(red: 0.95, green: 0.92, blue: 0.84),   // parchment
        secondaryText: Color(red: 0.78, green: 0.72, blue: 0.62), // faded ink
        titleDesign: .serif)

    /// A neutral theme for the Home screen (outside any casino) — the app's dark base.
    static let home = riverwood

    /// The theme for a casino, by id (D-066).
    static func theme(for casino: Casino) -> CasinoTheme {
        switch casino.id {
        case "skypool":    return .skypool
        case "clocktower": return .clockTower
        default:           return .riverwood
        }
    }

    /// The theme for a table, from the casino that hosts it.
    static func theme(forTable tableID: String) -> CasinoTheme {
        Casinos.casino(hosting: tableID).map(theme(for:)) ?? .riverwood
    }
}
