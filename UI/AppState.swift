// AppState.swift
// =====================================================================
// The app-level navigation + wallet state (D-035/D-036, generalised in D-065): where
// the player is (Home → Casino → Table) and how many CHIPS they own. The chips
// themselves live in GameWorld (`PlayerAccount`); this observable mirrors them for
// SwiftUI and drives navigation. Injected into the view tree from the app root.
//
// Navigation is now casino-agnostic: a screen is Home, a specific `Casino`, or a
// specific `CasinoTable`. Sitting down deducts the table's buy-in; leaving returns to
// the casino the table belongs to (D-065). The old Riverwood-specific entry points
// are gone — the same code path serves every casino.

import Foundation
import GameWorld

@MainActor
public final class AppState: ObservableObject {

    /// The three explicit levels of the app (D-035/D-065). The table level carries the
    /// concrete `CasinoTable` so the root can build the right game screen (Texas, Draw
    /// or Omaha) with the right rules.
    public enum Screen: Equatable {
        case home
        case casino(Casino)
        case table(CasinoTable)
    }

    @Published public var screen: Screen = .home
    @Published public private(set) var chips: Int

    private let account: PlayerAccount
    /// The casino a table was entered from, so leaving returns there (D-065).
    private var casinoContext: Casino?

    public init(account: PlayerAccount) {
        self.account = account
        self.chips = account.chips
    }

    // MARK: - Navigation

    public func goHome() { screen = .home }

    /// Enters a casino's lobby. Remembers it so leaving a table returns here.
    public func openCasino(_ casino: Casino) {
        casinoContext = casino
        screen = .casino(casino)
    }

    /// Whether the player can sit at a table with the given buy-in.
    public func canAfford(_ buyIn: Int) -> Bool { account.canAfford(buyIn) }

    /// Sits at a table: deducts its buy-in (chips → table fiches) and navigates.
    /// Returns the starting fiches (the buy-in), or nil if the player can't afford it.
    /// In free-play mode the buy-in is ignored but the fiches are still granted (D-050).
    @discardableResult
    public func sitDown(_ table: CasinoTable) -> Int? {
        guard account.buyIn(table.buyIn) else { return nil }
        chips = account.chips
        screen = .table(table)
        return table.buyIn
    }

    /// Stands up: converts the remaining table fiches back to chips and returns to the
    /// casino the table belongs to. A bust cashes out 0.
    public func leaveTable(cashingOut remaining: Int) {
        account.cashOut(remaining)
        chips = account.chips
        screen = casinoContext.map(Screen.casino) ?? .home
    }
}
