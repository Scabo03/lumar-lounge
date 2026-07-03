// EventHub.swift
// =====================================================================
// The multicast fan-out behind the session driver's event stream (D-015).
//
// An actor owns the set of live subscriptions, so subscribing and emitting are
// serialized without any lock or thread of our own — pure Swift Concurrency.
// Each subscriber gets its own `AsyncStream`; the hub yields every event to all
// subscribers whose viewer is allowed to see it. Buffering is unbounded, so the
// producer (the driver) never blocks waiting for a slow consumer — the stream
// runs at code speed and pacing is the consumer's concern.
//
// GameWorld only.

import Foundation

/// Fan-out of `SessionEvent`s to any number of independent subscribers.
actor EventHub {
    private var subscribers: [Int: (viewer: EventViewer, continuation: AsyncStream<SessionEvent>.Continuation)] = [:]
    private var nextSubscriberID = 0
    private var nextSequence = 0

    /// Registers a subscriber and returns its live stream. The subscriber
    /// receives public events, plus its own private events if it watches as a
    /// specific player.
    func subscribe(as viewer: EventViewer) -> AsyncStream<SessionEvent> {
        var madeContinuation: AsyncStream<SessionEvent>.Continuation!
        let stream = AsyncStream<SessionEvent>(bufferingPolicy: .unbounded) { continuation in
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

    /// Emits an event (assigning it the next chronological sequence number) to
    /// every subscriber allowed to see it.
    func emit(_ payload: EventPayload, audience: EventAudience) {
        let event = SessionEvent(sequence: nextSequence, audience: audience, payload: payload)
        nextSequence += 1
        for (_, subscriber) in subscribers where delivers(audience, to: subscriber.viewer) {
            subscriber.continuation.yield(event)
        }
    }

    /// Ends all streams, so consumers' `for await` loops terminate cleanly.
    func finishAll() {
        for (_, subscriber) in subscribers {
            subscriber.continuation.finish()
        }
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
