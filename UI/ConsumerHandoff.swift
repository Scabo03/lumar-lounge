// ConsumerHandoff.swift
// =====================================================================
// The handoff between "the producer has finished telling us what happened" and
// "the player may now act" — and the safety belt that sits behind it (D-106).
//
// THE DEFECT THIS EXISTS TO PREVENT. Every table view model drains its driver
// with the same three tasks: `relay` appends stream events to a queue,
// `produce` runs the driver at code speed, and `consume` alternates between
// presenting the next queued event and offering the human suspension. That loop
// used to decide between the two by sampling two independently-updated sources
// ACROSS a suspension point:
//
//     if !eventQueue.isEmpty { present(...) }          // sampled synchronously
//     else if let ctx = await human.pendingTurn { ... } // ...then an actor hop
//
// The actor hop is a window in which `relay` can append the very events that
// describe what just happened. The loop then acts on the stale decision and
// offers the turn anyway — so the buttons go live over a hand the player has
// not been shown, and because `runTurn` suspends the SAME loop that drains the
// queue, those events stay frozen until the player acts. The only key that
// unfreezes the interface is another press, and that press is a live game
// action: at blackjack it draws a real second card.
//
// THE ORDERING GUARANTEE THAT MAKES THE FIX SOUND. Every driver emits all the
// events describing a new state BEFORE it asks for the next decision — `emit`
// happens-before `provideAction`, in all seven games. So when a request for
// input appears, everything that explains the state the player is being asked
// about is ALREADY in the stream. It is simply not necessarily in this
// consumer's own queue yet: there is a third buffer (the AsyncStream) between
// the hub and `eventQueue`, so re-reading `eventQueue` alone is not enough.
// Letting the relay settle and re-checking is.
//
// The correction therefore lives entirely in the CONSUMER. No driver is slowed,
// no producer learns about the human rhythm (D-018).

import Foundation

@MainActor
enum ConsumerHandoff {

    /// How many times to let the relay run before concluding the consumer is
    /// caught up. Both `relay` and `consume` are main-actor isolated, so a
    /// `Task.yield()` from the consumer hands the actor to any relay
    /// continuation already enqueued — which, by the ordering guarantee above,
    /// it must be. Two would do; three is margin, and it costs nothing when
    /// there is nothing else to run.
    static let settleYields = 3

    /// Whether the consumer has presented everything the producer emitted
    /// before asking for input.
    ///
    /// Returns `false` the moment anything is still undelivered, so the caller
    /// can go back and present it instead of offering the turn.
    static func isCaughtUp(_ queueIsEmpty: () -> Bool,
                           yields: Int = settleYields) async -> Bool {
        for _ in 0..<yields {
            if !queueIsEmpty() { return false }
            await Task.yield()
        }
        return queueIsEmpty()
    }
}

/// THE SAFETY BELT (D-106) — a layer of protection deliberately INDEPENDENT of
/// the correctness of the flow above.
///
/// In a game with irreversible actions, a press must never act on a state the
/// player has not been shown. The flow fix makes that state impossible; this
/// makes it harmless if it ever returns. The worst case then degrades from
/// "a blind second card that busts a winning hand" to "a frozen interface",
/// which is recoverable.
///
/// It has two independent gates, and they catch different things:
///
///  • **Correspondence** — the caller's check that what is on screen IS what the
///    player is being asked about. Not a heuristic at all, and the gate that
///    still holds if the flow defect ever comes back: with a stale display every
///    press is refused, so the worst case is a frozen interface instead of a
///    blind irreversible action.
///
///  • **Freshness** (`isSettled`) — a temporal floor separating a finger bounce
///    from a decision. It is NOT a perception budget: perception is protected by
///    the flow fix, which shows and speaks the new state before the turn is
///    offered at all.
///
/// THE FLOOR IS MEASURED FROM THE PLAYER'S PREVIOUS ACTION, NOT FROM THE MOMENT
/// THE DECISION APPEARED — and that distinction is the whole difference between
/// a safety belt and a new defect. Timed from the decision's appearance, every
/// turn would begin with its buttons dead for the length of the floor, and a
/// quick player's FIRST, entirely legitimate press would be swallowed. Timed
/// from the previous action, a first press is always accepted instantly, while
/// a second press can only be honoured once the player has had longer than a
/// bounce to have learnt anything new. A deliberate second decision — press, the
/// card lands, perceive it, decide, press again — is comfortably outside it even
/// for a fast sighted player; a finger bounce or a double-tap is well inside.
@MainActor
struct InputReadiness {

    /// The finger-bounce separator, chosen against human motor behaviour rather
    /// than against the machine.
    static let defaultSettle: TimeInterval = 0.35

    /// Zero under `-uiTesting` and in unit tests, where input is delivered by a
    /// program rather than a finger and there is no bounce to separate.
    var settle: TimeInterval
    /// Injectable so freshness is testable without sleeping.
    var now: () -> TimeInterval

    private var lastAccepted: TimeInterval?

    init(settle: TimeInterval = defaultSettle,
         now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }) {
        self.settle = settle
        self.now = now
    }

    /// Whether enough has passed since the player's previous action for a new
    /// press to be a fresh decision rather than a bounce of the same one.
    /// True when there is no previous action to bounce off, so the first press
    /// of a hand is never delayed.
    var isSettled: Bool {
        guard let lastAccepted else { return true }
        return now() - lastAccepted >= settle
    }

    /// Records an accepted action, opening the bounce window behind it.
    mutating func accept() { lastAccepted = now() }

    /// A new decision sequence (a fresh hand or round): nothing to bounce off.
    mutating func reset() { lastAccepted = nil }
}
