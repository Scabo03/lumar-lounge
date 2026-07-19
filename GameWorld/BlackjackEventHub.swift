// BlackjackEventHub.swift
// =====================================================================
// Multicast fan-out of the blackjack event stream.
//
// Sister of the poker hubs (D-015/D-043/D-077): a deliberate small
// duplicate per game rather than a generic forced over unrelated event
// taxonomies. Buffering is unbounded so the driver never blocks on a slow
// consumer — pacing belongs to the consumer, never to the producer.

import Foundation

actor BlackjackEventHub {

    private var subscribers: [Int: (viewer: EventViewer,
                                    continuation: AsyncStream<BlackjackSessionEvent>.Continuation)] = [:]
    private var nextSubscriberID = 0
    private var nextSequence = 0

    func subscribe(as viewer: EventViewer) -> AsyncStream<BlackjackSessionEvent> {
        let id = nextSubscriberID
        nextSubscriberID += 1
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            subscribers[id] = (viewer, continuation)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id) }
            }
        }
    }

    private func removeSubscriber(_ id: Int) {
        subscribers[id] = nil
    }

    func emit(_ payload: BlackjackEventPayload, audience: EventAudience = .everyone) {
        let event = BlackjackSessionEvent(sequence: nextSequence, audience: audience, payload: payload)
        nextSequence += 1
        for (_, subscriber) in subscribers where delivers(audience, to: subscriber.viewer) {
            subscriber.continuation.yield(event)
        }
    }

    func finishAll() {
        for (_, subscriber) in subscribers {
            subscriber.continuation.finish()
        }
        subscribers.removeAll()
    }

    private func delivers(_ audience: EventAudience, to viewer: EventViewer) -> Bool {
        switch (audience, viewer) {
        case (.everyone, _):                     return true
        case let (.player(a), .player(b)):       return a == b
        case (.player, .spectator):              return false
        }
    }
}
