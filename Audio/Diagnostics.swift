// Diagnostics.swift
// =====================================================================
// A PERSISTENT, HIGH-RESOLUTION TRACE RECORDER for the spoken / audio / UI
// channels (D-107). It exists to diagnose the recurring VoiceOver rhythm defects
// — truncated announcements, a wager box that opens over an unfinished line, a
// re-read of the hand instead of the board — WITHOUT guessing: it records what
// actually happens, on the device, and writes it to a file the session can read
// back afterwards.
//
// WHY IT LIVES IN Audio. Audio is the one module every other imports (it is
// cross-cutting, D-023), so a single recorder here is reachable from the
// announcement queue, the speech conductor, the audio engine AND every UI view
// model — without threading a dependency through the layers or letting a lower
// module reach up. It knows nothing about poker; it just records opaque records.
//
// WHAT IT GUARANTEES.
//  • OFF by default. When disabled, `record` is a cheap early return — no lock,
//    no allocation — so it cannot weigh on normal play (the accessibility
//    constraint: it must never affect the game or the spoken channel).
//  • It NEVER speaks, plays, or posts to VoiceOver. It only writes to a file, so
//    it cannot interfere with the very channels it measures.
//  • Monotonic clock for ordering/durations (immune to wall-clock jumps) AND a
//    wall timestamp for correlation. Both on every record.
//  • Captures the REAL rendered text a caller hands it — never a localization
//    key — because a measurement of what the player HEARS on identifiers is
//    worthless (the D-091/D-093 lesson). Callers pass already-localized strings.
//  • JSON Lines, one self-contained object per line, flushed frequently so a
//    crash or a force-quit loses at most the last few records.

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The project-wide diagnostic trace recorder (D-107). A singleton so every layer
/// writes to the same file; gated, so it is inert unless deliberately enabled.
public final class Diagnostics {

    public static let shared = Diagnostics()

    /// Read WITHOUT the lock so a disabled recorder costs nothing on the hot path.
    /// A benign race at the enable/disable boundary at most drops or adds one record.
    public private(set) var isEnabled = false

    private let lock = NSLock()
    private var handle: FileHandle?
    private var fileURL: URL?
    private var seq = 0
    private var startUptimeNanos: UInt64 = 0
    private var writesSinceSync = 0

    private init() {}

    /// The file currently being written, for export (nil if not recording).
    public var currentFileURL: URL? { lock.lock(); defer { lock.unlock() }; return fileURL }

    // MARK: - Lifecycle

    /// Begins recording to a fresh file. Safe to call more than once (the previous
    /// file is closed first). `label` names the session in the header record.
    ///
    /// - Parameter url: an explicit destination (used by the collaudo test). When
    ///   nil, a timestamped file under `Documents/LumarDiagnostics/` — the app's
    ///   own container, retrievable over the cable via Finder file sharing.
    @discardableResult
    public func enable(url: URL? = nil, label: String = "session") -> URL? {
        lock.lock(); defer { lock.unlock() }
        closeLocked()

        let destination = url ?? Self.defaultURL()
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let h = try FileHandle(forWritingTo: destination)
            handle = h
            fileURL = destination
            seq = 0
            startUptimeNanos = DispatchTime.now().uptimeNanoseconds
            writesSinceSync = 0
            isEnabled = true
        } catch {
            handle = nil; fileURL = nil; isEnabled = false
            print("[Diagnostics] could not open trace file: \(error)")
            return nil
        }

        // Header: everything needed to interpret the trace on its own.
        var header: [String: Any] = [
            "label": label,
            "wallStart": Date().timeIntervalSince1970,
            "iso": Self.iso(Date()),
        ]
        #if canImport(UIKit)
        header["device"] = UIDevice.current.model
        header["system"] = UIDevice.current.systemVersion
        header["voiceOverRunning"] = UIAccessibility.isVoiceOverRunning
        #else
        header["device"] = "host"
        #endif
        recordLocked("session.begin", header)
        return fileURL
    }

    /// Stops recording and flushes. Idempotent.
    public func disable() {
        lock.lock(); defer { lock.unlock() }
        if isEnabled { recordLocked("session.end", ["wallEnd": Date().timeIntervalSince1970]) }
        closeLocked()
        isEnabled = false
    }

    private func closeLocked() {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        fileURL = nil
    }

    // MARK: - Recording

    /// Appends one record: `{seq, t (monotonic s), w (wall s), main (bool), k, …fields}`.
    /// A no-op — one boolean read — when disabled. All field values must be JSON
    /// scalars (String / Int / Double / Bool); anything else is stringified, and a
    /// non-finite Double is coerced to 0 so the line is always valid JSON.
    public func record(_ kind: String, _ fields: [String: Any] = [:]) {
        guard isEnabled else { return }
        lock.lock(); defer { lock.unlock() }
        recordLocked(kind, fields)
    }

    private func recordLocked(_ kind: String, _ fields: [String: Any]) {
        guard let handle else { return }
        seq += 1
        let mono = Double(DispatchTime.now().uptimeNanoseconds &- startUptimeNanos) / 1_000_000_000

        var object: [String: Any] = [
            "seq": seq,
            "t": mono,
            "w": Date().timeIntervalSince1970,
            "main": Thread.isMainThread,
            "k": kind,
        ]
        for (key, value) in fields { object[key] = Self.sanitize(value) }

        let line: Data
        if JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
            line = data
        } else {
            // Last-resort fallback: never lose a record to an encoding edge case.
            let fallback = "{\"seq\":\(seq),\"t\":\(mono),\"k\":\"\(kind)\",\"encodeError\":true}"
            line = Data(fallback.utf8)
        }
        handle.write(line)
        handle.write(Data([0x0A]))   // newline

        writesSinceSync += 1
        if writesSinceSync >= 20 { try? handle.synchronize(); writesSinceSync = 0 }
    }

    private static func sanitize(_ value: Any) -> Any {
        switch value {
        case let d as Double: return d.isFinite ? d : 0
        case let f as Float:  return f.isFinite ? Double(f) : 0
        case is String, is Int, is Bool, is Int64: return value
        default: return String(describing: value)
        }
    }

    // MARK: - Helpers

    private static func defaultURL() -> URL {
        let docs = (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let stamp = Int(Date().timeIntervalSince1970)
        return docs.appendingPathComponent("LumarDiagnostics/trace-\(stamp).jsonl")
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}
