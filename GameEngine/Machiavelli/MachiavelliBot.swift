// MachiavelliBot.swift
// =====================================================================
// What a "bot" is from the Machiavelli engine's point of view, the redacted view it
// is allowed to see, the plan it returns for a whole turn, and the budget that bounds
// its search.
//
// HONEST INFORMATION (D-009, as in every engine): a bot never sees opponents' hands.
// It receives a `MachiavelliBotContext` carrying only PUBLIC state — the table, the
// stock size, and how many cards each opponent HOLDS (a count is public; the cards
// are not) — plus its OWN hand. Opponents' cards are structurally absent.
//
// A Machiavelli turn is a sequence of transformations, so a bot does not return one
// action: it returns a `MachiavelliTurnPlan` — the whole table it wants to leave
// behind and how it wants to end the turn (meld-and-pass, or draw). The driver
// validates the plan through the SAME turn model / predicate a human would use, so a
// bot cannot cheat the rules.
//
// Foundation only.

import Foundation

/// A decider that plans one whole Machiavelli turn for the seat on turn.
public protocol MachiavelliBot {
    /// Plan a turn given the redacted, seat-relative view of the game.
    func planTurn(_ context: MachiavelliBotContext) -> MachiavelliTurnPlan
}

// MARK: - Redacted context

/// The public state of one seat at a Machiavelli table — crucially NO hand cards,
/// only how many cards the seat holds (public information).
public struct MachiavelliPublicSeat: Hashable, Sendable {
    public let id: Int
    public let handCount: Int
    public let isHero: Bool

    public init(id: Int, handCount: Int, isHero: Bool) {
        self.id = id
        self.handCount = handCount
        self.isHero = isHero
    }
}

/// A seat-relative, public-only snapshot of a Machiavelli game at a decision point.
public struct MachiavelliBotContext: Sendable {
    /// The acting seat's id.
    public let heroSeatID: Int
    /// The acting seat's own hand.
    public let hand: [Card]
    /// The shared table (public).
    public let table: [Meld]
    /// Cards left in the stock (public count).
    public let stockCount: Int
    /// Public state of every seat (no hand cards, only counts).
    public let seats: [MachiavelliPublicSeat]
    /// Deterministic fingerprint of this public situation + the hero's hand, so a bot
    /// mixed with its own seed reproduces its choice in an identical spot.
    public let fingerprint: UInt64

    public init(heroSeatID: Int, hand: [Card], table: [Meld], stockCount: Int,
                seats: [MachiavelliPublicSeat]) {
        self.heroSeatID = heroSeatID
        self.hand = hand
        self.table = table
        self.stockCount = stockCount
        self.seats = seats

        var fp: UInt64 = 0xcbf2_9ce4_8422_2325
        func feed(_ value: UInt64) { fp = botMix64(fp ^ value) }
        feed(UInt64(bitPattern: Int64(heroSeatID)))
        feed(UInt64(bitPattern: Int64(stockCount)))
        for card in hand.sorted(by: cardOrder) { feed(card.fingerprintCode) }
        for meld in table {
            feed(0xF00D)
            for card in meld.cards { feed(card.fingerprintCode) }
        }
        self.fingerprint = fp
    }
}

// MARK: - Turn plan

/// How a bot wants to end its turn.
public enum MachiavelliTerminal: Equatable, Sendable {
    /// Leave the (new) table in place and pass — legal only if ≥1 hand card was placed.
    case meld
    /// Place nothing and draw one card from the stock.
    case draw
}

/// A bot's plan for a whole turn: the table it proposes to leave behind, and how it
/// ends the turn. For `.draw`, `finalTable` is the table unchanged.
public struct MachiavelliTurnPlan: Equatable, Sendable {
    /// The proposed whole-table arrangement (a list of combinations) after the turn.
    public let finalTable: [[Card]]
    /// The terminal action closing the turn.
    public let terminal: MachiavelliTerminal

    public init(finalTable: [[Card]], terminal: MachiavelliTerminal) {
        self.finalTable = finalTable
        self.terminal = terminal
    }

    /// The "do nothing but draw" plan: keep the table as-is and draw.
    public static func drawing(keeping table: [Meld]) -> MachiavelliTurnPlan {
        MachiavelliTurnPlan(finalTable: table.map { $0.cards }, terminal: .draw)
    }
}

// MARK: - Search budget

/// Bounds a bot's turn search so it ALWAYS returns the best move found so far and
/// NEVER overruns (D-070). Two independent caps; the search stops at whichever is hit
/// first:
///
///  • `maxNodes` — a DETERMINISTIC ceiling on search nodes. Same seed + same node
///    budget ⇒ identical plan. This is what makes the bot reproducible for tests and
///    is also the structural "depth" knob (a shallow bot has a low ceiling and returns
///    early even when time remains — the young player who just glances).
///
///  • `maxTime` — a wall-clock cap (monotonic `ContinuousClock`). In production the
///    search keeps refining until this elapses, then returns its best — adaptive to
///    table complexity and machine speed. It is the hard anti-overrun guarantee.
///
/// Determinism note (the reconciliation): the RESULT is deterministic given a seed AND
/// a node budget. Under a pure time cap the number of refinements varies by machine,
/// so the plan may vary — documented and intended (production is time-adaptive, tests
/// pin the node budget). See D-070.
public struct MachiavelliSearchBudget: Equatable, Sendable {
    public var maxNodes: Int?
    public var maxTime: Duration?

    public init(maxNodes: Int? = nil, maxTime: Duration? = nil) {
        self.maxNodes = maxNodes
        self.maxTime = maxTime
    }

    /// A purely deterministic budget of `nodes` search nodes (no clock). For tests.
    public static func nodes(_ nodes: Int) -> MachiavelliSearchBudget {
        MachiavelliSearchBudget(maxNodes: nodes, maxTime: nil)
    }

    /// A purely wall-clock budget of `duration` (no node ceiling). For overrun tests.
    public static func time(_ duration: Duration) -> MachiavelliSearchBudget {
        MachiavelliSearchBudget(maxNodes: nil, maxTime: duration)
    }
}

// MARK: - Shared ordering helper

/// A total, deterministic order on cards (rank then suit) used across the engine so
/// hands/tables hash and iterate reproducibly.
@inline(__always)
func cardOrder(_ a: Card, _ b: Card) -> Bool {
    (a.rank.rawValue, a.suit.rawValue) < (b.rank.rawValue, b.suit.rawValue)
}
