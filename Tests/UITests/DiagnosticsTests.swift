// DiagnosticsTests.swift
// =====================================================================
// COLLAUDO of the diagnostic recorder (D-107), as a deterministic test.
//
// The recorder's whole reason to exist is to let the session diagnose the
// VoiceOver rhythm defects from DATA, not hypotheses — so it must actually
// capture, and capture the REAL rendered text (the D-091/D-093 lesson: under
// `swift test` there is no bundle and strings become keys, which would make any
// measurement of what the player HEARS worthless). This test injects the shipped
// it.lproj via `UIStrings.override` so the module renders real Italian, drives
// real Blackjack and Texas sessions through the view models with recording
// pointed at a temp file, then reads the trace back and asserts:
//   • every core record kind is present (queue, conductor, audio, per-VM, focus);
//   • timestamps are monotonic;
//   • the captured spoken text is real Italian, never a bare localization key.
//
// The audio-engine hook (`a.play`) is exercised here too, because a bundle-less
// AudioEngine still records each play (as `started:false`), and the real-clip
// latency path is exercised separately by the on-device self-test harness.

import XCTest
@testable import UI
@testable import GameWorld
@testable import GameEngine
import Audio

@MainActor
final class DiagnosticsTests: XCTestCase {

    private var traceURL: URL!

    override func setUp() {
        super.setUp()
        UIStrings.override = BlackjackLocalizedStrings.italian   // real Italian, off the disk (D-093)
        traceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("diag-collaudo-\(UUID().uuidString).jsonl")
    }

    override func tearDown() {
        Diagnostics.shared.disable()
        UIStrings.override = nil
        try? FileManager.default.removeItem(at: traceURL)
        super.tearDown()
    }

    // MARK: - The collaudo

    func testTheRecorderCapturesEveryCoreChannelAndRealItalianText() async throws {
        Diagnostics.shared.enable(url: traceURL, label: "collaudo")

        try await driveBlackjack(decisions: 16)
        try await driveTexas(decisions: 8)

        Diagnostics.shared.disable()

        let records = try readTrace()
        XCTAssertGreaterThan(records.count, 100, "the run must actually produce a substantial trace")

        // 1. Every core record kind is captured — the queue, the conductor, the
        //    audio engine, the per-view-model hooks, and the header.
        let kinds = Set(records.compactMap { $0["k"] as? String })
        for required in ["session.begin", "session.end",
                         "ui.present", "ui.suspend", "ui.action",
                         "c.say", "q.enqueue", "q.speak.start", "q.speak.end",
                         "a.play"] {
            XCTAssertTrue(kinds.contains(required), "missing record kind: \(required)")
        }

        // 2. Every record carries the monotonic + wall clocks and a kind, and the
        //    monotonic clock never runs backwards.
        var lastT = -1.0
        for r in records {
            XCTAssertNotNil(r["k"] as? String)
            let t = try XCTUnwrap(r["t"] as? Double)
            XCTAssertNotNil(r["w"] as? Double)
            XCTAssertGreaterThanOrEqual(t, lastT, "monotonic clock went backwards")
            lastT = t
        }

        // 3. The header identifies the environment.
        let header = try XCTUnwrap(records.first { ($0["k"] as? String) == "session.begin" })
        XCTAssertEqual(header["label"] as? String, "collaudo")
        XCTAssertNotNil(header["device"])

        // 4. THE POINT (D-093): the captured spoken text is real Italian, never a
        //    bare localization key. A key has dots and no spaces
        //    ("blackjack.announce.deal.natural"); a real line has spaces.
        let spoken = capturedSpokenText(records)
        XCTAssertGreaterThan(spoken.count, 5, "the run must actually speak")
        let keyShaped = try NSRegularExpression(pattern: #"^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$"#)
        for text in spoken {
            let range = NSRange(text.startIndex..., in: text)
            XCTAssertNil(keyShaped.firstMatch(in: text, range: range),
                         "a captured spoken line is a raw localization key, not rendered text: \(text)")
        }
        XCTAssertTrue(spoken.contains { $0.contains(" ") },
                      "at least one captured line must be a real (spaced) sentence")
    }

    /// The safety property: with recording OFF, `record` writes nothing.
    func testRecordingIsInertWhenDisabled() throws {
        // Not enabled in this test.
        XCTAssertFalse(Diagnostics.shared.isEnabled)
        Diagnostics.shared.record("should.not.appear", ["x": 1])
        XCTAssertNil(Diagnostics.shared.currentFileURL)
    }

    // MARK: - Driving real sessions (mirrors DecisionHandoffTests)

    private func driveBlackjack(decisions target: Int) async throws {
        let store = UserDefaults(suiteName: "diag.test.bj.\(UUID().uuidString)")!
        let model = BlackjackTableViewModel(seed: 4242, fastMode: true,
                                            audio: AudioEngine(configureSession: false),
                                            mode: AppVoiceOverMode(store: store),
                                            rules: .riverwood, returnLabel: "x")
        let run = Task { await model.run() }
        defer { run.cancel() }
        var ticks = 0, decisions = 0
        while ticks < 3000, decisions < target, model.outcome == nil {
            if model.betBox != nil {
                model.confirmBet()
            } else if let turn = model.turn {
                decisions += 1
                if turn.legal.allowed.contains(.hit), turn.total < 17 { model.hit() } else { model.stand() }
            }
            try await Task.sleep(nanoseconds: 3_000_000)
            ticks += 1
        }
    }

    private func driveTexas(decisions target: Int) async throws {
        let store = UserDefaults(suiteName: "diag.test.texas.\(UUID().uuidString)")!
        let model = TableViewModel(seed: 20260811, fastMode: true,
                                   audio: AudioEngine(configureSession: false),
                                   mode: AppVoiceOverMode(store: store),
                                   rules: .classic, returnLabel: "x")
        let run = Task { await model.run() }
        defer { run.cancel() }
        var ticks = 0, decisions = 0
        while ticks < 3000, decisions < target, model.outcome == nil {
            if model.humanTurn != nil { decisions += 1; model.checkOrCall() }
            try await Task.sleep(nanoseconds: 3_000_000)
            ticks += 1
        }
    }

    // MARK: - Reading the trace back

    private func readTrace() throws -> [[String: Any]] {
        let text = try String(contentsOf: traceURL, encoding: .utf8)
        return text.split(separator: "\n").compactMap {
            guard let data = $0.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
    }

    /// Every non-empty spoken/synthesised string the trace captured.
    private func capturedSpokenText(_ records: [[String: Any]]) -> [String] {
        var out: [String] = []
        for r in records {
            for key in ["text", "synthesis", "fallback"] {
                if let s = r[key] as? String, !s.isEmpty { out.append(s) }
            }
        }
        return out
    }
}
