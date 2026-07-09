// DrawEventHub.swift
// =====================================================================
// The multicast fan-out behind the Five-Card Draw session driver's event stream
// (D-043). Same model as the Texas `EventHub` (an actor owning the subscriptions,
// unbounded buffering, public/private routing) but typed to `DrawSessionEvent`.
//
// A deliberate, small duplication rather than a forced generic abstraction over
// the two event types (D-042): the two games' streams stay independent, and the
// Texas driver is left untouched.
//
// GameWorld only.

import Foundation

/// Fan-out of `DrawSessionEvent`s to any number of independent subscribers.
actor DrawEventHub {
    private var subscribers: [Int: (viewer: EventViewer, continuation: AsyncStream<DrawSessionEvent>.Continuation)] = [:]
    private var nextSubscriberID = 0
    private var nextSequence = 0

    func subscribe(as viewer: EventViewer) -> AsyncStream<DrawSessionEvent> {
        var madeContinuation: AsyncStream<DrawSessionEvent>.Continuation!
        let stream = AsyncStream<DrawSessionEvent>(bufferingPolicy: .unbounded) { continuation in
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
    func emit(_ payload: DrawEventPayload, audience: EventAudience) {
        let event = DrawSessionEvent(sequence: nextSequence, audience: audience, payload: payload)
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
