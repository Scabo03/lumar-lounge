// DrawBot.swift
// =====================================================================
// What a "bot" is from the Five-Card Draw engine's point of view, and the two
// redacted views it is allowed to see: one to choose a betting action, one to
// choose which cards to exchange.
//
// HONEST INFORMATION (as in Hold'em, D-009): a bot never receives the raw
// `FiveCardDrawHand` (which holds everyone's cards). It receives a context that
// carries only public state — pot, bets, positions, and each opponent's DISCARD
// COUNT, which is public once drawn — plus its OWN five cards. Opponents' cards
// are structurally absent.
//
// Foundation only.

import Foundation

/// A decider that plays Five-Card Draw: it both bets and exchanges cards.
public protocol DrawBot {
    /// Choose a legal betting action for the seat on turn.
    func decideAction(_ context: DrawBotContext) -> DrawAction
    /// Choose which of the seat's own cards (0…4) to discard in the draw.
    func decideDiscards(_ context: DrawDrawContext) -> [Card]
}

/// The PUBLIC state of one seat at a Five-Card Draw table — no cards, but the
/// number of cards it exchanged (public information once it has drawn).
public struct DrawPublicSeat: Hashable, Sendable {
    public let id: Int
    public let stack: Int
    public let streetBet: Int
    public let totalBet: Int
    public let hasFolded: Bool
    public let isAllIn: Bool
    public let isOpener: Bool
    public let hasDrawn: Bool
    /// Cards exchanged in the draw, or `nil` if the seat hasn't drawn yet.
    public let discardCount: Int?
    public let isHero: Bool
}

/// A seat-relative, public-only snapshot for a BETTING decision.
public struct DrawBotContext: Sendable {
    public let heroSeatID: Int
    /// The acting seat's own five cards.
    public let cards: [Card]
    public let phase: DrawPhase
    public let potSize: Int
    public let currentBet: Int
    public let toCall: Int
    public let heroStack: Int
    public let legal: DrawLegalActions
    public let seats: [DrawPublicSeat]
    /// Opponents still live (not folded), excluding the hero.
    public let activeOpponents: Int
    /// 0 = earliest to act (left of button) … 1 = latest (button).
    public let lateness: Double
    /// Emotional temperature from the driver (0 = calm). Defaults to calm.
    public let emotionalTemperature: Double
    /// CONTEXTUAL personality override the driver applies for a boosted (decisive)
    /// hand (D-053): added to the bot's aggression this hand only. 0 = no boost. The
    /// bot's permanent `Personality` is never changed — this is per-context.
    public let aggressionBonus: Double
    /// CONTEXTUAL scale on the bot's trashFoldTendency this hand only (D-053):
    /// 1 = unchanged, 0.5 = folds half as much garbage. Per-context, not permanent.
    public let trashFoldScale: Double
    /// Deterministic fingerprint of this public situation + the hero's cards.
    public let fingerprint: UInt64

    public init(heroSeatID: Int,
                cards: [Card],
                phase: DrawPhase,
                potSize: Int,
                currentBet: Int,
                toCall: Int,
                heroStack: Int,
                legal: DrawLegalActions,
                seats: [DrawPublicSeat],
                activeOpponents: Int,
                lateness: Double,
                emotionalTemperature: Double = 0,
                aggressionBonus: Double = 0,
                trashFoldScale: Double = 1) {
        self.heroSeatID = heroSeatID
        self.cards = cards
        self.phase = phase
        self.potSize = potSize
        self.currentBet = currentBet
        self.toCall = toCall
        self.heroStack = heroStack
        self.legal = legal
        self.seats = seats
        self.activeOpponents = activeOpponents
        self.lateness = lateness
        self.emotionalTemperature = emotionalTemperature
        self.aggressionBonus = aggressionBonus
        self.trashFoldScale = trashFoldScale

        var fp: UInt64 = 0xcbf2_9ce4_8422_2325
        func feed(_ value: UInt64) { fp = botMix64(fp ^ value) }
        feed(UInt64(bitPattern: Int64(heroSeatID)))
        feed(UInt64(phase.rawValue))
        feed(UInt64(bitPattern: Int64(potSize)))
        feed(UInt64(bitPattern: Int64(currentBet)))
        feed(UInt64(bitPattern: Int64(toCall)))
        feed(UInt64(bitPattern: Int64(heroStack)))
        for card in cards { feed(card.fingerprintCode) }
        self.fingerprint = fp
    }

    /// Builds the redacted betting context for the seat on turn in `hand`, or
    /// `nil` if `hand` is not currently asking a seat to bet.
    public init?(actingIn hand: FiveCardDrawHand, emotionalTemperature: Double = 0,
                 aggressionBonus: Double = 0, trashFoldScale: Double = 1) {
        guard let heroID = hand.actingSeatID, let legal = hand.legalActions() else { return nil }
        guard let hero = hand.seats.first(where: { $0.id == heroID }) else { return nil }

        let n = hand.seats.count
        let heroIndex = hand.seats.firstIndex { $0.id == heroID }!
        let toCall = max(0, hand.currentBet - hero.streetBet)
        let opponents = hand.seats.filter { !$0.hasFolded && $0.id != heroID }.count
        let lateness = n > 1
            ? Double((heroIndex - (hand.buttonIndex + 1) + n) % n) / Double(n - 1)
            : 0
        let publicSeats = hand.seats.map {
            DrawPublicSeat(id: $0.id, stack: $0.stack, streetBet: $0.streetBet, totalBet: $0.totalBet,
                           hasFolded: $0.hasFolded, isAllIn: $0.isAllIn, isOpener: $0.isOpener,
                           hasDrawn: $0.hasDrawn, discardCount: $0.hasDrawn ? $0.discardCount : nil,
                           isHero: $0.id == heroID)
        }

        self.init(heroSeatID: heroID, cards: hero.cards, phase: hand.phase,
                  potSize: hand.pot, currentBet: hand.currentBet, toCall: toCall,
                  heroStack: hero.stack, legal: legal, seats: publicSeats,
                  activeOpponents: opponents, lateness: lateness,
                  emotionalTemperature: emotionalTemperature,
                  aggressionBonus: aggressionBonus, trashFoldScale: trashFoldScale)
    }
}

/// A seat-relative, public-only snapshot for a DRAW (discard) decision.
public struct DrawDrawContext: Sendable {
    public let heroSeatID: Int
    /// The acting seat's own five cards.
    public let cards: [Card]
    /// Opponents still live (not folded), excluding the hero.
    public let activeOpponents: Int
    /// 0 = earliest to draw (left of button) … 1 = latest (button).
    public let lateness: Double
    public let emotionalTemperature: Double
    public let fingerprint: UInt64

    public init(heroSeatID: Int,
                cards: [Card],
                activeOpponents: Int,
                lateness: Double,
                emotionalTemperature: Double = 0) {
        self.heroSeatID = heroSeatID
        self.cards = cards
        self.activeOpponents = activeOpponents
        self.lateness = lateness
        self.emotionalTemperature = emotionalTemperature

        var fp: UInt64 = 0x100_0000_01b3
        func feed(_ value: UInt64) { fp = botMix64(fp ^ value) }
        feed(UInt64(bitPattern: Int64(heroSeatID)))
        feed(UInt64(bitPattern: Int64(activeOpponents)))
        for card in cards { feed(card.fingerprintCode) }
        self.fingerprint = fp
    }

    /// Builds the redacted draw context for the seat whose draw it is in `hand`,
    /// or `nil` if `hand` is not currently asking a seat to draw.
    public init?(drawingIn hand: FiveCardDrawHand, emotionalTemperature: Double = 0) {
        guard let options = hand.drawOptions() else { return nil }
        guard let hero = hand.seats.first(where: { $0.id == options.seatID }) else { return nil }
        let n = hand.seats.count
        let heroIndex = hand.seats.firstIndex { $0.id == hero.id }!
        let opponents = hand.seats.filter { !$0.hasFolded && $0.id != hero.id }.count
        let lateness = n > 1
            ? Double((heroIndex - (hand.buttonIndex + 1) + n) % n) / Double(n - 1)
            : 0
        self.init(heroSeatID: hero.id, cards: hero.cards, activeOpponents: opponents,
                  lateness: lateness, emotionalTemperature: emotionalTemperature)
    }
}
