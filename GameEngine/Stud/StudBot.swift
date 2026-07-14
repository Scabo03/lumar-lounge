// StudBot.swift
// =====================================================================
// What a "bot" is from the Stud engine's point of view, and the redacted view of a hand
// it is allowed to see.
//
// HONEST INFORMATION (D-009, as in every engine): a bot never receives the raw
// `StudHand` (which holds everyone's DOWN cards). It receives a `StudBotContext`
// carrying only public state — pots, stacks, betting, positions — plus its OWN full
// seven-in-progress cards, AND every seat's face-UP cards. The up cards ARE public in
// Stud (that is the whole game), so a bot legitimately sees opponents' up cards; their
// DOWN cards are structurally absent (D-077).
//
// Foundation only.

import Foundation

/// A decider that chooses one legal action for the seat on turn in Stud.
public protocol StudBot {
    /// Choose an action permitted by `context.legal`.
    func decide(_ context: StudBotContext) -> StudAction
}

/// The PUBLIC state of one seat at a Stud table: its chips and betting, plus its face-UP
/// cards — but NEVER its down cards.
public struct StudPublicSeat: Hashable, Sendable {
    public let id: Int
    public let stack: Int
    public let streetBet: Int
    public let totalBet: Int
    /// The seat's face-UP cards this hand (public in Stud). Empty for a folded seat.
    public let upCards: [Card]
    public let hasFolded: Bool
    public let isAllIn: Bool
    public let isHero: Bool

    public init(id: Int, stack: Int, streetBet: Int, totalBet: Int, upCards: [Card],
                hasFolded: Bool, isAllIn: Bool, isHero: Bool) {
        self.id = id
        self.stack = stack
        self.streetBet = streetBet
        self.totalBet = totalBet
        self.upCards = upCards
        self.hasFolded = hasFolded
        self.isAllIn = isAllIn
        self.isHero = isHero
    }
}

/// A seat-relative, public-only snapshot of a Stud hand at a decision point.
public struct StudBotContext: Sendable {
    /// The acting seat's id.
    public let heroSeatID: Int
    /// The acting seat's own DOWN cards (private).
    public let holeCards: [Card]
    /// The acting seat's own face-UP cards (also visible to everyone).
    public let upCards: [Card]
    public let street: StudStreet
    /// Total chips already wagered across all pots.
    public let potSize: Int
    /// The bet level to match this street.
    public let currentBet: Int
    /// Chips the hero must put in to call (0 if it can check).
    public let toCall: Int
    public let heroStack: Int
    /// The table's minimum full bet size (the "small bet" analogue).
    public let bet: Int
    /// The legal actions for the hero, straight from the engine.
    public let legal: StudLegalActions
    /// Public state of every seat — INCLUDING each seat's up cards (Stud's public info).
    public let seats: [StudPublicSeat]
    /// Opponents still in the hand (not folded), excluding the hero.
    public let activeOpponents: Int
    /// Whether the bet was raised beyond the bring-in / checked-around this street.
    public let aggressionFacedThisStreet: Bool
    /// Emotional temperature fed by the driver (0 = calm, >0 = on tilt).
    public let emotionalTemperature: Double
    /// Deterministic fingerprint of this public situation + the hero's cards.
    public let fingerprint: UInt64

    /// The hero's own seven-in-progress cards (down + up).
    public var heroCards: [Card] { holeCards + upCards }

    public init(heroSeatID: Int,
                holeCards: [Card],
                upCards: [Card],
                street: StudStreet,
                potSize: Int,
                currentBet: Int,
                toCall: Int,
                heroStack: Int,
                bet: Int,
                legal: StudLegalActions,
                seats: [StudPublicSeat],
                activeOpponents: Int,
                aggressionFacedThisStreet: Bool,
                emotionalTemperature: Double = 0) {
        self.heroSeatID = heroSeatID
        self.holeCards = holeCards
        self.upCards = upCards
        self.street = street
        self.potSize = potSize
        self.currentBet = currentBet
        self.toCall = toCall
        self.heroStack = heroStack
        self.bet = bet
        self.legal = legal
        self.seats = seats
        self.activeOpponents = activeOpponents
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
        for card in holeCards { feed(card.fingerprintCode) }
        for card in upCards { feed(card.fingerprintCode) }
        // Opponents' up cards are part of the decision, so they enter the fingerprint too.
        for seat in seats where !seat.isHero {
            for card in seat.upCards { feed(card.fingerprintCode &+ 7) }
        }
        self.fingerprint = fp
    }

    /// Builds the redacted context for the seat currently on turn in `hand`, or `nil` if
    /// the hand is complete / no one is to act.
    public init?(actingIn hand: StudHand, emotionalTemperature: Double = 0) {
        guard let heroID = hand.actingSeatID, let legal = hand.legalActions() else { return nil }
        guard let hero = hand.seats.first(where: { $0.id == heroID }) else { return nil }

        let toCall = max(0, hand.currentBet - hero.streetBet)
        let pot = hand.seats.reduce(0) { $0 + $1.totalBet }
        let opponents = hand.seats.filter { !$0.hasFolded && $0.id != heroID }.count
        let facedAggression = hand.currentBet > (hand.street == .third ? hand.bringIn : 0)

        // Public per-seat state carries the UP cards (public); a folded seat shows none.
        let publicSeats = hand.seats.map {
            StudPublicSeat(id: $0.id, stack: $0.stack, streetBet: $0.streetBet, totalBet: $0.totalBet,
                           upCards: $0.hasFolded ? [] : $0.upCards,
                           hasFolded: $0.hasFolded, isAllIn: $0.isAllIn, isHero: $0.id == heroID)
        }

        self.init(heroSeatID: heroID,
                  holeCards: hero.holeCards,
                  upCards: hero.upCards,
                  street: hand.street,
                  potSize: pot,
                  currentBet: hand.currentBet,
                  toCall: toCall,
                  heroStack: hero.stack,
                  bet: hand.bet,
                  legal: legal,
                  seats: publicSeats,
                  activeOpponents: opponents,
                  aggressionFacedThisStreet: facedAggression,
                  emotionalTemperature: emotionalTemperature)
    }
}
