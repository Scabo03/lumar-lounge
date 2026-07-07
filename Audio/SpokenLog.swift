// SpokenLog.swift
// =====================================================================
// One DEBUG-gated switch for ALL audio-spoken logging (D-030/D-032): the engine's
// actual playbacks, the speech conductor's enqueues, and the announcement queue's
// posts/drops. Silent in release; the code stays in the repo for future debugging.
//
//   #if DEBUG
//   SpokenLog.enabled = true
//   #endif

import Foundation

public enum SpokenLog {
    #if DEBUG
    /// Master switch. Set true to print every audio-spoken event with a timestamp.
    public static var enabled = false

    public static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        print("[Spoken] \(String(format: "%.3f", Date().timeIntervalSince1970)) \(message())")
    }
    #else
    @inline(__always) public static func log(_ message: @autoclosure () -> String) {}
    #endif
}
