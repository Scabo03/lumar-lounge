// Casino.swift
// =====================================================================
// The reusable CASINO pattern (D-065). A casino is a container that hosts TABLES;
// each table declares WHICH game it runs, its buy-in, its bot personalities and its
// rules. Some games recur across casinos with different parameters (Texas Hold'em is
// a generic table present everywhere; each casino has its own SPECIALITY — Five-Card
// Draw at the Riverwood, Omaha at the Skypool). What changes casino-to-casino is not
// which games exist but WHO sits at them — the personalities and difficulty of that
// specific place.
//
// This was extracted when the second casino (Skypool) arrived: hardcoding a second
// casino by hand would have duplicated the lobby and left the generalisation to do
// with the code already copied. The Riverwood, after this extraction, behaves exactly
// as before — same tables, same buy-ins, same bots, same determinism (D-065).
//
// These are pure value types (Equatable/Sendable), so they can live inside the
// app-level navigation state and be diffed for animation. GameWorld only.

import Foundation
import GameEngine

/// Which game a casino table runs, carrying that game's full rules object. The three
/// rules types stay distinct (the engines are parallel and independent, D-038/D-061);
/// this enum is the single place the app switches on to build the right table screen.
public enum CasinoGame: Equatable, Sendable {
    case texas(TableRules)
    case draw(DrawTableRules)
    case omaha(OmahaTableRules)
    case machiavelli(MachiavelliTableRules)
    case stud(StudTableRules)
    case blackjack(BlackjackTableRules)

    /// The buy-in required to sit — the sole economic barrier to a table (D-065). For
    /// Machiavelli it is a refundable entry threshold (prestige, not money — D-072).
    public var buyIn: Int {
        switch self {
        case let .texas(rules): return rules.buyIn
        case let .draw(rules): return rules.buyIn
        case let .omaha(rules): return rules.buyIn
        case let .machiavelli(rules): return rules.buyIn
        case let .stud(rules): return rules.buyIn
        case let .blackjack(rules): return rules.buyIn
        }
    }
}

/// One table hosted by a casino: a stable id (also its accessibility identifier and
/// navigation key), the localized title/subtitle keys, and the game it runs.
public struct CasinoTable: Identifiable, Equatable, Sendable {
    /// Stable, unique id — e.g. "riverwood.table.classic". Doubles as the row's
    /// accessibility identifier (preserving the existing Riverwood identifiers) and
    /// the SwiftUI `.id` that gives each sit-down a fresh session.
    public let id: String
    /// The localized key for the table's game title (e.g. "table.holdem.title").
    public let titleKey: String
    /// The localized key for the table's style/room subtitle (e.g. "table.style.fast").
    public let subtitleKey: String
    public let game: CasinoGame

    public var buyIn: Int { game.buyIn }

    public init(id: String, titleKey: String, subtitleKey: String, game: CasinoGame) {
        self.id = id
        self.titleKey = titleKey
        self.subtitleKey = subtitleKey
        self.game = game
    }
}

/// A casino: an id, its display name (a proper noun, not localized), the localized
/// keys for its tagline and its home-screen blurb, the key for its return label, and
/// the tables it hosts.
public struct Casino: Identifiable, Equatable, Sendable {
    public let id: String
    /// Proper-noun display name shown on screen (not a localized string — a name).
    public let displayName: String
    /// The localized key for the VoiceOver-SPOKEN rendering of the name, when the
    /// visible English name doesn't read right in the target voice (D-060). `nil` →
    /// the visible `displayName` is spoken as-is. E.g. "Skypool" reads wrong for the
    /// Italian voice, so the Skypool declares the ear-verified spelling "Skai pul".
    public let spokenNameKey: String?
    public let taglineKey: String
    public let blurbKey: String
    /// The localized key for the "return to <casino>" label on the end-of-game
    /// overlay — Italian articles differ per name, so each casino names its own.
    public let returnLabelKey: String
    public let tables: [CasinoTable]

    public init(id: String, displayName: String, spokenNameKey: String? = nil,
                taglineKey: String, blurbKey: String, returnLabelKey: String, tables: [CasinoTable]) {
        self.id = id
        self.displayName = displayName
        self.spokenNameKey = spokenNameKey
        self.taglineKey = taglineKey
        self.blurbKey = blurbKey
        self.returnLabelKey = returnLabelKey
        self.tables = tables
    }
}

/// The registry of casinos. Adding a casino is now a data change here — no lobby
/// code to duplicate (D-065).
public enum Casinos {

    /// The Riverwood: the first casino, UNCHANGED by the generalisation — exactly the
    /// tables, buy-ins and bots it had before (D-065). Its table ids reproduce the
    /// pre-existing accessibility identifiers the UI tests rely on.
    public static let riverwood = Casino(
        id: "riverwood",
        displayName: "Riverwood Casinò",
        taglineKey: "riverwood.tagline",
        blurbKey: "home.riverwood.blurb",
        returnLabelKey: "endgame.return",
        tables: [
            CasinoTable(id: "riverwood.table.classic",
                        titleKey: "table.holdem.title", subtitleKey: "table.style.classic",
                        game: .texas(.classic)),
            CasinoTable(id: "riverwood.table.fast",
                        titleKey: "table.holdem.title", subtitleKey: "table.style.fast",
                        game: .texas(.fast)),
            CasinoTable(id: "riverwood.table.draw",
                        titleKey: "table.draw.title", subtitleKey: "table.draw.room",
                        game: .draw(.riverwoodWhiskey)),
            CasinoTable(id: "riverwood.table.blackjack",
                        titleKey: "table.blackjack.title", subtitleKey: "table.blackjack.riverwood",
                        game: .blackjack(.riverwood)),
        ])

    /// The Skypool: a modern, urban, marble-and-water city casino (D-065/D-066). Its
    /// SPECIALITY is Omaha Pot Limit at the "Marble" table; it also hosts the two
    /// generic Texas tables (Classic/Fast) with its own, tougher urban bots. Buy-ins
    /// are ~5× the corresponding Riverwood tables, in an increasing scale: Fast is the
    /// cheapest, Classic a little more, Marble (the speciality) sensibly the highest.
    public static let skypool = Casino(
        id: "skypool",
        displayName: "Skypool Casinò",
        spokenNameKey: "skypool.spoken.a11y",   // ear-verified "Skai pul" (D-060/D-066)
        taglineKey: "skypool.tagline",
        blurbKey: "home.skypool.blurb",
        returnLabelKey: "endgame.return.skypool",
        tables: [
            CasinoTable(id: "skypool.table.fast",
                        titleKey: "table.holdem.title", subtitleKey: "table.style.fast",
                        game: .texas(.skypoolFast)),
            CasinoTable(id: "skypool.table.classic",
                        titleKey: "table.holdem.title", subtitleKey: "table.style.classic",
                        game: .texas(.skypoolClassic)),
            CasinoTable(id: "skypool.table.marble",
                        titleKey: "table.omaha.title", subtitleKey: "table.omaha.marble",
                        game: .omaha(.skypoolMarble)),
            CasinoTable(id: "skypool.table.blackjack",
                        titleKey: "table.blackjack.title", subtitleKey: "table.blackjack.skypool",
                        game: .blackjack(.skypool)),
        ])

    /// The ClockTower: a small, exclusive, ACADEMIC casino in an ancient tower, tied to
    /// the university — erudite, refined, played for PRESTIGE not money (D-072). A third
    /// axis, not a step above the Skypool: Riverwood is the frontier, Skypool the money,
    /// ClockTower the prestige — and, being refundable, the MOST ACCESSIBLE economically.
    /// It hosts a SINGLE table for now: Machiavelli. (The roadmap gives it Seven-Card
    /// Stud as a future poker speciality — NOT anticipated here, no placeholder.)
    public static let clockTower = Casino(
        id: "clocktower",
        displayName: "ClockTower",
        spokenNameKey: "clocktower.spoken.a11y",   // ear-verify before producing voices (D-060)
        taglineKey: "clocktower.tagline",
        blurbKey: "home.clocktower.blurb",
        returnLabelKey: "endgame.return.clocktower",
        tables: [
            CasinoTable(id: "clocktower.table.machiavelli",
                        titleKey: "table.machiavelli.title", subtitleKey: "table.machiavelli.room",
                        game: .machiavelli(.clockTower)),
            // The tower's POKER speciality: Seven-Card Stud Pot Limit, the hardest game,
            // where the House rewards a win (D-077/D-078).
            CasinoTable(id: "clocktower.table.stud",
                        titleKey: "table.stud.title", subtitleKey: "table.stud.room",
                        game: .stud(.clockTower)),
        ])

    /// Every casino, in home-screen order.
    public static let all: [Casino] = [riverwood, skypool, clockTower]

    /// The casino a table belongs to (for return navigation / labels).
    public static func casino(hosting tableID: String) -> Casino? {
        all.first { $0.tables.contains { $0.id == tableID } }
    }
}
