// BlackjackSpeechMap.swift
// =====================================================================
// The authoritative event → spoken-source mapping for blackjack (D-029),
// and the one place its lines are rendered into text.
//
// THE PROBLEM THIS FILE EXISTS TO SOLVE (D-091).
// Blackjack is fast. A round is two cards and a decision, and a sighted
// player gets through dozens in a few minutes. If every round carried a
// poker-sized load of announcements, the blind player would get a SLOW
// version of the one game that is supposed to be quick — the sighted player
// fast, the blind player crawling. That is precisely "someone loses
// something", and it is a failure of the project's premise.
//
// So the essential announcement is compressed to the MINIMUM NEEDED TO
// DECIDE: your total, and the dealer's up card. One short line. Everything
// else — which cards make up the total, what the dealer is showing in
// detail — is reachable on demand from accessible elements
// (`BlackjackReadout`), never pushed at the player every round.
//
// And the boundary holds without exception: this file DESCRIBES the state
// and NEVER advises the move. Blackjack has a famous optimal strategy and it
// would be trivial to whisper it. Saying "sixteen, the dealer shows ten" is
// description; saying "you should hit" is advice, and the sighted player
// gets none.

import Foundation
import GameEngine
import GameWorld
import Audio

public struct BlackjackSpeechPlan: Equatable, Sendable {
    public var croupier: SoundID?
    public var synthesis: BlackjackSynthLine?
    public var croupierFallback: BlackjackSynthLine?

    public init(croupier: SoundID? = nil,
                synthesis: BlackjackSynthLine? = nil,
                croupierFallback: BlackjackSynthLine? = nil) {
        self.croupier = croupier
        self.synthesis = synthesis
        self.croupierFallback = croupierFallback
    }

    public static let silent = BlackjackSpeechPlan()
}

/// Resolved data, not text: `text(for:)` is the single rendering point, so
/// `plan(...)` stays pure and testable against cases rather than strings.
public enum BlackjackSynthLine: Equatable, Sendable {
    /// The one essential line: what you have, what the dealer shows.
    case deal(total: Int, isSoft: Bool, dealerUpCard: Card, isNatural: Bool)
    /// Only ever spoken when the player holds more than one hand.
    case handTurn(index: Int, count: Int, total: Int, isSoft: Bool)
    case drew(card: Card, total: Int, isSoft: Bool, didBust: Bool)
    case doubled(card: Card, total: Int, isSoft: Bool, didBust: Bool)
    case split(handCount: Int)
    case dealer(cards: [Card], total: Int, isSoft: Bool, didBust: Bool, hasNatural: Bool)
    case settled(index: Int, handCount: Int, outcome: BlackjackOutcome, amount: Int)
    case roundNet(net: Int)
    case sessionWon
    case sessionLost
}

public enum BlackjackSpeechMap {

    // MARK: - The mapping

    public static func plan(for payload: BlackjackEventPayload) -> BlackjackSpeechPlan {
        switch payload {

        case .sessionBegan, .roundBegan, .shoeShuffled:
            // The wager the player just chose does not need saying back: the
            // button already carries it (D-055). The shuffle is a sound, not
            // a sentence.
            return .silent

        case let .dealt(_, total, isSoft, dealerUpCard, isNatural):
            return BlackjackSpeechPlan(
                synthesis: .deal(total: total, isSoft: isSoft,
                                 dealerUpCard: dealerUpCard, isNatural: isNatural))

        case let .handTurnBegan(handIndex, _, total, isSoft, handCount):
            // With a single hand this would repeat what the deal line just
            // said — the player knows whose turn it is by the structure of the
            // game (D-089). It earns its place only after a split, where
            // several hands really do need telling apart.
            guard handCount > 1 else { return .silent }
            return BlackjackSpeechPlan(
                synthesis: .handTurn(index: handIndex, count: handCount,
                                     total: total, isSoft: isSoft))

        case let .playerActed(_, action, _):
            return plan(for: action)

        case let .dealerPlayed(cards, total, isSoft, didBust, hasNatural, _):
            return BlackjackSpeechPlan(
                synthesis: .dealer(cards: cards, total: total, isSoft: isSoft,
                                   didBust: didBust, hasNatural: hasNatural))

        case let .handSettled(handIndex, handCount, outcome, _, bet, net):
            return BlackjackSpeechPlan(
                synthesis: .settled(index: handIndex, handCount: handCount,
                                    outcome: outcome, amount: amount(outcome, bet: bet, net: net)))

        case let .roundEnded(_, net, _, handCount):
            // With one hand the settlement line already gave the number; a
            // summary would only repeat it. Several hands genuinely need adding up.
            guard handCount > 1 else { return .silent }
            return BlackjackSpeechPlan(synthesis: .roundNet(net: net))

        case .sessionEnded:
            return .silent
        }
    }

    private static func plan(for action: BlackjackActedAction) -> BlackjackSpeechPlan {
        switch action {
        case let .hit(card, total, isSoft, didBust):
            return BlackjackSpeechPlan(
                synthesis: .drew(card: card, total: total, isSoft: isSoft, didBust: didBust))

        case let .doubled(card, total, _, didBust):
            return BlackjackSpeechPlan(
                synthesis: .doubled(card: card, total: total, isSoft: false, didBust: didBust))

        case let .split(hands, _):
            return BlackjackSpeechPlan(synthesis: .split(handCount: hands.count))

        case .stood, .surrendered:
            // The player pressed the button; it spoke for itself, and the
            // settlement line carries the consequence.
            return .silent
        }
    }

    /// The figure a settlement line quotes: what the player gains, keeps back
    /// or loses. Always the REAL number for that hand (D-087).
    private static func amount(_ outcome: BlackjackOutcome, bet: Int, net: Int) -> Int {
        switch outcome {
        case .natural, .win:   return net           // what it earned
        case .push:            return bet           // what came back
        case .lose, .bust:     return bet           // what it cost
        case .surrender:       return bet - (bet / 2)
        }
    }

    // MARK: - Rendering

    /// The localization seam. Defaulted, so callers never see it — but it lets
    /// the load measurement render the REAL Italian text, which matters because
    /// `uiLocalized` falls back to the key when the bundle is absent under
    /// `swift test`, and a measurement of key lengths would be worthless.
    public typealias Localizer = (String, [CVarArg]) -> String
    public static let standard: Localizer = { uiLocalizedList($0, $1) }

    /// A card as blackjack speaks it: THE RANK ONLY.
    ///
    /// In blackjack the suit carries no information whatsoever — it cannot
    /// affect a total, a payout or a legal move. Saying "ten of clubs" instead
    /// of "ten" spends a second of the player's round on something that cannot
    /// change a single decision, every round, forever. The suit stays visible
    /// on the table and stays on the interrogable elements for anyone who wants
    /// it; it simply does not ride in the line the player hears every hand.
    public static func spokenRank(_ card: Card, localized: Localizer = standard) -> String {
        localized("card.rank.\(card.rank.rawValue)", [])
    }

    public static func text(for line: BlackjackSynthLine,
                            localized: Localizer = standard) -> String {
        switch line {

        case let .deal(total, isSoft, dealerUpCard, isNatural):
            let dealer = spokenRank(dealerUpCard, localized: localized)
            if isNatural {
                return localized("blackjack.announce.deal.natural", [dealer])
            }
            return localized("blackjack.announce.deal",
                             [totalPhrase(total, isSoft, localized: localized), dealer])

        case let .handTurn(index, count, total, isSoft):
            return localized("blackjack.announce.handturn",
                             [index + 1, count, totalPhrase(total, isSoft, localized: localized)])

        case let .drew(card, total, isSoft, didBust):
            let drawn = spokenRank(card, localized: localized)
            return didBust
                ? localized("blackjack.announce.hit.bust", [drawn, total])
                : localized("blackjack.announce.hit",
                            [drawn, totalPhrase(total, isSoft, localized: localized)])

        case let .doubled(card, total, isSoft, didBust):
            let drawn = spokenRank(card, localized: localized)
            return didBust
                ? localized("blackjack.announce.double.bust", [drawn, total])
                : localized("blackjack.announce.double",
                            [drawn, totalPhrase(total, isSoft, localized: localized)])

        case let .split(handCount):
            return localized("blackjack.announce.split", [handCount])

        case let .dealer(_, total, isSoft, didBust, hasNatural):
            // The dealer's TOTAL is the whole of what the result turns on. The
            // cards that built it are detail, and they were the single longest
            // line in the round when measured — they live on the dealer element
            // instead, reachable whenever the player wants them.
            if hasNatural { return localized("blackjack.announce.dealer.natural", []) }
            return didBust
                ? localized("blackjack.announce.dealer.bust", [total])
                : localized("blackjack.announce.dealer",
                            [totalPhrase(total, isSoft, localized: localized)])

        case let .settled(index, handCount, outcome, amount):
            let body = settlementText(outcome, amount: amount, localized: localized)
            guard handCount > 1 else { return body }
            return localized("blackjack.result.hand", [index + 1, body])

        case let .roundNet(net):
            if net > 0 { return localized("blackjack.round.net.positive", [net]) }
            if net < 0 { return localized("blackjack.round.net.negative", [-net]) }
            return localized("blackjack.round.net.zero", [])

        case .sessionWon:  return localized("blackjack.session.won", [])
        case .sessionLost: return localized("blackjack.session.lost", [])
        }
    }

    private static func settlementText(_ outcome: BlackjackOutcome,
                                       amount: Int,
                                       localized: Localizer) -> String {
        switch outcome {
        case .natural:   return localized("blackjack.result.natural", [amount])
        case .win:       return localized("blackjack.result.win", [amount])
        case .push:      return localized("blackjack.result.push", [amount])
        case .lose:      return localized("blackjack.result.lose", [amount])
        case .bust:      return localized("blackjack.result.bust", [amount])
        case .surrender: return localized("blackjack.result.surrender", [amount])
        }
    }

    /// A total, and whether it is soft — the distinction that actually changes
    /// what the hand can do, and the only adjective the player is given.
    public static func totalPhrase(_ total: Int, _ isSoft: Bool,
                                   localized: Localizer = standard) -> String {
        isSoft ? localized("blackjack.total.soft", [total])
               : localized("blackjack.total.hard", [total])
    }

    // MARK: - Priority

    /// Blackjack is a game the player plays alone against the house, so almost
    /// everything spoken is personal and none of it is chatter: nothing here is
    /// `.low`, and the lines that carry money are never droppable.
    public static func priority(for line: BlackjackSynthLine) -> AnnouncementPriority {
        switch line {
        case .deal, .settled, .roundNet, .sessionWon, .sessionLost, .drew, .doubled:
            return .high
        case .handTurn, .split, .dealer:
            return .medium
        }
    }
}
