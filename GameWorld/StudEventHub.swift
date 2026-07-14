// StudEventHub.swift
// =====================================================================
// The multicast fan-out behind the Stud session driver's event stream. Same model as
// the other games' hubs (an actor owning the subscriptions, unbounded buffering,
// public/private routing) but typed to `StudSessionEvent`.
//
// A deliberate, small duplication rather than a forced generic over the game event
// types (D-042/D-043/D-077): the games' streams stay independent, and the other engines
// are left untouched. GameWorld only.

import Foundation

/// Fan-out of `StudSessionEvent`s to any number of independent subscribers.
actor StudEventHub {
    private var subscribers: [Int: (viewer: EventViewer, continuation: AsyncStream<StudSessionEvent>.Continuation)] = [:]
    private var nextSubscriberID = 0
    private var nextSequence = 0

    func subscribe(as viewer: EventViewer) -> AsyncStream<StudSessionEvent> {
        var madeContinuation: AsyncStream<StudSessionEvent>.Continuation!
        let stream = AsyncStream<StudSessionEvent>(bufferingPolicy: .unbounded) { continuation in
            madeContinuation = continuation
        }
        let id = nextSubscriberID
        nextSubscriberID += 1
        subscribers[id] = (viewer, madeContinuation)
        madeContinuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    private func removeSubscriber(_ id: Int) {
        subscribers[id] = nil
    }

    /// Emits an event (assigning the next chronological sequence number) to every
    /// subscriber allowed to see it.
    func emit(_ payload: StudEventPayload, audience: EventAudience) {
        let event = StudSessionEvent(sequence: nextSequence, audience: audience, payload: payload)
        nextSequence += 1
        for (_, subscriber) in subscribers where delivers(audience, to: subscriber.viewer) {
            subscriber.continuation.yield(event)
        }
    }

    /// Ends all streams so consumers' `for await` loops terminate cleanly.
    func finishAll() {
        for (_, subscriber) in subscribers { subscriber.continuation.finish() }
        subscribers.removeAll()
    }

    private func delivers(_ audience: EventAudience, to viewer: EventViewer) -> Bool {
        switch audience {
        case .everyone:
            return true
        case .player(let target):
            if case .player(let watcher) = viewer { return watcher == target }
            return false
        }
    }
}
