// MachiavelliEventHub.swift
// =====================================================================
// The multicast fan-out behind the Machiavelli session driver's event stream. Same
// proven model as the poker hubs (an actor owning subscriptions, unbounded buffering,
// public/private routing) but typed to `MachiavelliSessionEvent`. A deliberate, small
// duplication rather than a forced generic over the four event types (D-042/D-043),
// keeping the games' streams independent. GameWorld only.

import Foundation

/// Fan-out of `MachiavelliSessionEvent`s to any number of independent subscribers.
actor MachiavelliEventHub {
    private var subscribers: [Int: (viewer: EventViewer, continuation: AsyncStream<MachiavelliSessionEvent>.Continuation)] = [:]
    private var nextSubscriberID = 0
    private var nextSequence = 0

    func subscribe(as viewer: EventViewer) -> AsyncStream<MachiavelliSessionEvent> {
        var madeContinuation: AsyncStream<MachiavelliSessionEvent>.Continuation!
        let stream = AsyncStream<MachiavelliSessionEvent>(bufferingPolicy: .unbounded) { continuation in
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
    func emit(_ payload: MachiavelliEventPayload, audience: EventAudience) {
        let event = MachiavelliSessionEvent(sequence: nextSequence, audience: audience, payload: payload)
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
