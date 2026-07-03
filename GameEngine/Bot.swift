// Bot.swift
// =====================================================================
// What a "bot" is from the engine's point of view, and the redacted view of a
// hand it is allowed to see.
//
// A bot is anything that, given a `BotContext` (a seat-relative, PUBLIC-ONLY
// snapshot of the hand), returns one legal `Action`. It attaches to the M1.2
// engine from the outside — reading `legalActions()` and calling `apply(_:)`
// like any other decider — without the engine needing changes.
//
// HONEST INFORMATION (D-009): `BotContext` is built so a bot structurally cannot
// see opponents' hole cards. `HoldemHand.seats` exposes everyone's `hole`, so we
// never hand the raw hand to a bot; we hand it a context that carries only the
// public per-seat state plus the acting seat's own two cards.
//
// Foundation only.

import Foundation

/// A decider that chooses one legal action for the seat on turn.
public protocol PokerBot {
    /// Choose an action given the redacted, seat-relative view of the hand.
    /// Implementations must return an action permitted by `context.legal`.
    func decide(_ context: BotContext) -> Action
}

/// The PUBLIC state of one seat, as any player at the table can see it —
/// crucially without hole cards.
public struct PublicSeat: Hashable, Sendable {
    public let id: Int
    public let stack: Int
    public let streetBet: Int
    public let totalBet: Int
    public let hasFolded: Bool
    public let isAllIn: Bool
    public let isHero: Bool
}

/// A seat-relative, public-only snapshot of a hand at a decision point.
///
/// Everything here is information the acting seat legitimately has: the board,
/// the pots and stacks, the betting so far, its position — plus its OWN two hole
/// cards. Opponents' hole cards are deliberately absent.
public struct BotContext: Sendable {
    /// The acting seat's id.
    public let heroSeatID: Int
    /// The acting seat's own two hole cards.
    public let hole: Hand
    public let board: [Card]
    public let street: Street
    /// Total chips already wagered across all pots.
    public let potSize: Int
    /// The bet level to match this street.
    public let currentBet: Int
    /// Chips the hero must put in to call (0 if it can check).
    public let toCall: Int
    public let heroStack: Int
    public let bigBlind: Int
    /// The legal actions for the hero, straight from the engine.
    public let legal: LegalActions
    /// Public state of every seat (no hole cards).
    public let seats: [PublicSeat]
    /// Opponents still in the hand (not folded), excluding the hero.
    public let activeOpponents: Int
    /// 0 = earliest to act (small-blind side) … 1 = latest (button).
    public let lateness: Double
    /// Whether the bet was raised beyond the blind/checked-around this street.
    public let aggressionFacedThisStreet: Bool
    /// Emotional temperature fed by the driver (0 = calm, >0 = on tilt). Lets a
    /// tilt-reactive personality drift after a bad beat. Defaults to calm.
    public let emotionalTemperature: Double
    /// Deterministic fingerprint of this public situation + the hero's cards.
    /// A bot mixes it with its own seed so identical situations reproduce.
    public let fingerprint: UInt64

    /// Designated initializer. Also usable directly to craft scenarios (tests,
    /// previews). The `fingerprint` is derived from the semantic fields.
    public init(heroSeatID: Int,
                hole: Hand,
                board: [Card],
                street: Street,
                potSize: Int,
                currentBet: Int,
                toCall: Int,
                heroStack: Int,
                bigBlind: Int,
                legal: LegalActions,
                seats: [PublicSeat],
                activeOpponents: Int,
                lateness: Double,
                aggressionFacedThisStreet: Bool,
                emotionalTemperature: Double = 0) {
        self.heroSeatID = heroSeatID
        self.hole = hole
        self.board = board
        self.street = street
        self.potSize = potSize
        self.currentBet = currentBet
        self.toCall = toCall
        self.heroStack = heroStack
        self.bigBlind = bigBlind
        self.legal = legal
        self.seats = seats
        self.activeOpponents = activeOpponents
        self.lateness = lateness
        self.aggressionFacedThisStreet = aggressionFacedThisStreet
        self.emotionalTemperature = emotionalTemperature

        var fp: UInt64 = 0xcbf2_9ce4_8422_2325
        func feed(_ value: UInt64) { fp = botMix64(fp ^ value) }
        feed(UInt64(bitPattern: Int64(heroSeatID)))
        feed(UInt64(street.rawValue))
        feed(UInt64(bitPattern: Int64(potSize)))
        feed(UInt64(bitPattern: Int64(currentBet)))
        feed(UInt64(bitPattern: Int64(toCall)))
        feed(UInt64(bitPattern: Int64(heroStack)))
        for card in hole.cards { feed(card.fingerprintCode) }
        for card in board { feed(card.fingerprintCode) }
        self.fingerprint = fp
    }

    /// Builds the redacted context for the seat currently on turn in `hand`,
    /// or `nil` if the hand is complete / no one is to act.
    public init?(actingIn hand: HoldemHand, emotionalTemperature: Double = 0) {
        guard let heroID = hand.actingSeatID, let legal = hand.legalActions() else { return nil }
        guard let hero = hand.seats.first(where: { $0.id == heroID }), let hole = hero.hole else { return nil }

        let n = hand.seats.count
        let heroIndex = hand.seats.firstIndex { $0.id == heroID }!
        let toCall = max(0, hand.currentBet - hero.streetBet)
        let pot = hand.seats.reduce(0) { $0 + $1.totalBet }
        let opponents = hand.seats.filter { !$0.hasFolded && $0.id != heroID }.count
        let lateness = n > 1
            ? Double((heroIndex - (hand.buttonIndex + 1) + n) % n) / Double(n - 1)
            : 0
        let facedAggression = hand.currentBet > (hand.street == .preflop ? hand.bigBlind : 0)

        let publicSeats = hand.seats.map {
            PublicSeat(id: $0.id, stack: $0.stack, streetBet: $0.streetBet, totalBet: $0.totalBet,
                       hasFolded: $0.hasFolded, isAllIn: $0.isAllIn, isHero: $0.id == heroID)
        }

        self.init(heroSeatID: heroID,
                  hole: hole,
                  board: hand.board,
                  street: hand.street,
                  potSize: pot,
                  currentBet: hand.currentBet,
                  toCall: toCall,
                  heroStack: hero.stack,
                  bigBlind: hand.bigBlind,
                  legal: legal,
                  seats: publicSeats,
                  activeOpponents: opponents,
                  lateness: lateness,
                  aggressionFacedThisStreet: facedAggression,
                  emotionalTemperature: emotionalTemperature)
    }
}

// MARK: - Deterministic helpers (shared by the bot layer)

/// SplitMix64 finalizer: a fast, well-mixed bijection on 64-bit values.
@inline(__always)
func botMix64(_ x: UInt64) -> UInt64 {
    var z = x &+ 0x9E37_79B9_7F4A_7C15
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
}

/// A uniform Double in [0, 1) drawn from a seeded generator.
@inline(__always)
func botUnit(_ generator: inout SeededGenerator) -> Double {
    Double(generator.next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
}

extension Card {
    /// Stable small integer code for hashing a card into a fingerprint.
    var fingerprintCode: UInt64 { UInt64(rank.rawValue * 4 + suit.rawValue) }
}
