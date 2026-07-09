// AppState.swift
// =====================================================================
// The app-level navigation + wallet state (D-035/D-036): where the player is
// (Home → Casino → Table) and how many CHIPS they own. The chips themselves live
// in GameWorld (`PlayerAccount`); this observable mirrors them for SwiftUI and
// drives navigation. Injected into the view tree from the app root.

import Foundation
import GameWorld

@MainActor
public final class AppState: ObservableObject {

    /// The three explicit levels of the app (D-035). The table level hosts either a
    /// Texas Hold'em table (by format) or the Five-Card Draw table (D-044).
    public enum Screen: Equatable {
        case home
        case riverwood
        case table(TableFormat)
        case drawTable
    }

    @Published public var screen: Screen = .home
    @Published public private(set) var chips: Int

    private let account: PlayerAccount

    public init(account: PlayerAccount) {
        self.account = account
        self.chips = account.chips
    }

    // MARK: - Navigation

    public func goHome() { screen = .home }
    public func openRiverwood() { screen = .riverwood }

    /// Whether the player can sit at a table with the given buy-in.
    public func canAfford(_ buyIn: Int) -> Bool { account.canAfford(buyIn) }

    /// Sits at a table: deducts the buy-in (chips → table fiches) and navigates.
    /// Returns the starting fiches, or nil if the player can't afford it.
    @discardableResult
    public func sitDown(_ style: TableFormat, buyIn: Int) -> Int? {
        guard account.buyIn(buyIn) else { return nil }
        chips = account.chips
        screen = .table(style)
        return buyIn
    }

    /// Sits at the Five-Card Draw table: deducts the buy-in and navigates (D-044).
    @discardableResult
    public func sitDownDraw(buyIn: Int) -> Int? {
        guard account.buyIn(buyIn) else { return nil }
        chips = account.chips
        screen = .drawTable
        return buyIn
    }

    /// Stands up: converts the remaining table fiches back to chips and returns to
    /// the Riverwood. A bust cashes out 0.
    public func leaveTable(cashingOut remaining: Int) {
        account.cashOut(remaining)
        chips = account.chips
        screen = .riverwood
    }
}
