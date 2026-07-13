// OmahaBot.swift
// =====================================================================
// What a "bot" is from the Omaha engine's point of view, and the redacted view of
// a hand it is allowed to see.
//
// HONEST INFORMATION (D-009, as in Hold'em and Draw): a bot never receives the raw
// `OmahaHand` (which holds everyone's cards). It receives an `OmahaBotContext`
// carrying only public state — board, pots, stacks, betting, positions — plus its
// OWN four hole cards. Opponents' cards are structurally absent.
//
// Foundation only.

import Foundation

/// A decider that chooses one legal action for the seat on turn in Omaha.
public protocol OmahaBot {
    /// Choose an action permitted by `context.legal`.
    func decide(_ context: OmahaBotContext) -> OmahaAction
}

/// The PUBLIC state of one seat at an Omaha table — no hole cards.
public struct OmahaPublicSeat: Hashable, Sendable {
    public let id: Int
    public let stack: Int
    public let streetBet: Int
    public let totalBet: Int
    public let hasFolded: Bool
    public let isAllIn: Bool
    public let isHero: Bool
}

/// A seat-relative, public-only snapshot of an Omaha hand at a decision point.
public struct OmahaBotContext: Sendable {
    /// The acting seat's id.
    public let heroSeatID: Int
    /// The acting seat's own FOUR hole cards.
    public let hole: [Card]
    public let board: [Card]
    public let street: OmahaStreet
    /// Total chips already wagered across all pots.
    public let potSize: Int
    /// The bet level to match this street.
    public let currentBet: Int
    /// Chips the hero must put in to call (0 if it can check).
    public let toCall: Int
    public let heroStack: Int
    public let bigBlind: Int
    /// The legal actions for the hero, straight from the engine.
    public let legal: OmahaLegalActions
    /// Public state of every seat (no hole cards).
    public let seats: [OmahaPublicSeat]
    /// Opponents still in the hand (not folded), excluding the hero.
    public let activeOpponents: Int
    /// 0 = earliest to act (small-blind side) … 1 = latest (button).
    public let lateness: Double
    /// Whether the bet was raised beyond the blind/checked-around this street.
    public let aggressionFacedThisStreet: Bool
    /// Emotional temperature fed by the driver (0 = calm, >0 = on tilt).
    public let emotionalTemperature: Double
    /// Deterministic fingerprint of this public situation + the hero's cards.
    public let fingerprint: UInt64

    public init(heroSeatID: Int,
                hole: [Card],
                board: [Card],
                street: OmahaStreet,
                potSize: Int,
                currentBet: Int,
                toCall: Int,
                heroStack: Int,
                bigBlind: Int,
                legal: OmahaLegalActions,
                seats: [OmahaPublicSeat],
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
        for card in hole { feed(card.fingerprintCode) }
        for card in board { feed(card.fingerprintCode) }
        self.fingerprint = fp
    }

    /// Builds the redacted context for the seat currently on turn in `hand`, or
    /// `nil` if the hand is complete / no one is to act.
    public init?(actingIn hand: OmahaHand, emotionalTemperature: Double = 0) {
        guard let heroID = hand.actingSeatID, let legal = hand.legalActions() else { return nil }
        guard let hero = hand.seats.first(where: { $0.id == heroID }) else { return nil }

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
            OmahaPublicSeat(id: $0.id, stack: $0.stack, streetBet: $0.streetBet, totalBet: $0.totalBet,
                            hasFolded: $0.hasFolded, isAllIn: $0.isAllIn, isHero: $0.id == heroID)
        }

        self.init(heroSeatID: heroID,
                  hole: hero.holeCards,
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
