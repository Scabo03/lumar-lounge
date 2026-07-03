// HandGate.swift
// =====================================================================
// A tiny async gate that keeps the (code-speed) session producer at most one
// hand ahead of the (human-paced) consumer (D-018).
//
// Without it, the driver would compute the whole session instantly and buffer
// thousands of events before the first one is shown — front-loading all the
// bots' Monte Carlo work. With it, the producer plays one hand, then waits for
// the consumer to finish narrating that hand before playing the next.

import Foundation

/// A counting gate: `acquire()` suspends until a permit is available;
/// `release()` grants one (resuming the longest waiter). Starts with one permit
/// so the first hand may begin immediately.
actor HandGate {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(initialPermits: Int = 1) {
        self.permits = initialPermits
    }

    func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            permits += 1
        }
    }
}
