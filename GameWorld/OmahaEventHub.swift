// OmahaEventHub.swift
// =====================================================================
// The multicast fan-out behind the Omaha session driver's event stream. Same model
// as the Texas `EventHub` and Draw `DrawEventHub` (an actor owning the subscriptions,
// unbounded buffering, public/private routing) but typed to `OmahaSessionEvent`.
//
// A deliberate, small duplication rather than a forced generic over the three event
// types (D-042/D-043): the games' streams stay independent, and Texas and Draw are
// left untouched. GameWorld only.

import Foundation

/// Fan-out of `OmahaSessionEvent`s to any number of independent subscribers.
actor OmahaEventHub {
    private var subscribers: [Int: (viewer: EventViewer, continuation: AsyncStream<OmahaSessionEvent>.Continuation)] = [:]
    private var nextSubscriberID = 0
    private var nextSequence = 0

    func subscribe(as viewer: EventViewer) -> AsyncStream<OmahaSessionEvent> {
        var madeContinuation: AsyncStream<OmahaSessionEvent>.Continuation!
        let stream = AsyncStream<OmahaSessionEvent>(bufferingPolicy: .unbounded) { continuation in
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
    func emit(_ payload: OmahaEventPayload, audience: EventAudience) {
        let event = OmahaSessionEvent(sequence: nextSequence, audience: audience, payload: payload)
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
