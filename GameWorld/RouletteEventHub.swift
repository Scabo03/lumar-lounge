// RouletteEventHub.swift
// =====================================================================
// Multicast fan-out of the roulette event stream — sister of the other hubs
// (D-015/D-090). A deliberate small duplicate per game rather than a generic
// forced over unrelated taxonomies; buffering is unbounded so the producer
// never blocks on a slow consumer (pacing belongs to the consumer, D-018).

import Foundation

actor RouletteEventHub {

    private var subscribers: [Int: (viewer: EventViewer,
                                    continuation: AsyncStream<RouletteSessionEvent>.Continuation)] = [:]
    private var nextSubscriberID = 0
    private var nextSequence = 0

    func subscribe(as viewer: EventViewer) -> AsyncStream<RouletteSessionEvent> {
        let id = nextSubscriberID
        nextSubscriberID += 1
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            subscribers[id] = (viewer, continuation)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id) }
            }
        }
    }

    private func removeSubscriber(_ id: Int) { subscribers[id] = nil }

    func emit(_ payload: RouletteEventPayload, audience: EventAudience = .everyone) {
        let event = RouletteSessionEvent(sequence: nextSequence, audience: audience, payload: payload)
        nextSequence += 1
        for (_, subscriber) in subscribers where delivers(audience, to: subscriber.viewer) {
            subscriber.continuation.yield(event)
        }
    }

    func finishAll() {
        for (_, subscriber) in subscribers { subscriber.continuation.finish() }
        subscribers.removeAll()
    }

    private func delivers(_ audience: EventAudience, to viewer: EventViewer) -> Bool {
        switch (audience, viewer) {
        case (.everyone, _):               return true
        case let (.player(a), .player(b)): return a == b
        case (.player, .spectator):        return false
        }
    }
}
