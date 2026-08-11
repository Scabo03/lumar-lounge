// DiagnosticsSelfTest.swift
// =====================================================================
// COLLAUDO of the diagnostic recorder (D-107), on the real device/simulator.
//
// The user has been burned before by instrumentation that turned out not to be
// recording once they started playing. This harness, launched with
// `-diagnosticsSelfTest`, proves the WHOLE pipeline end to end BEFORE the app is
// handed over: it enables the recorder to its real `Documents/` file path, drives
// real Blackjack and Texas sessions through the real view models (so the per-VM,
// queue, conductor and audio-engine hooks all fire against the bundled mp3s and
// the real localized strings), then reads the trace BACK and prints a histogram
// of what was captured plus a few real spoken lines. If the console shows the
// categories and Italian text, the recorder works.
//
// It replaces the app for the run (like PacingBench), so it enables the recorder
// itself rather than relying on AppRootView.

import Foundation
import GameWorld
import Audio

@MainActor
public enum DiagnosticsSelfTest {

    public static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-diagnosticsSelfTest")
    }

    private static func line(_ s: String) { print("DIAG-SELFTEST \(s)"); fflush(stdout) }

    public static func run() async {
        line("=== DIAGNOSTICS SELF-TEST ===")
        let url = Diagnostics.shared.enable(label: "selftest")
        line("trace file: \(url?.path ?? "<none>")")

        await driveBlackjack(decisions: 24)
        await driveTexas(decisions: 12)

        Diagnostics.shared.disable()
        summarize(url)
        line("=== END ===")
    }

    // MARK: - Drive real view models (mirrors the DecisionHandoffTests harness)

    private static func driveBlackjack(decisions target: Int) async {
        line("--- blackjack ---")
        let store = UserDefaults(suiteName: "diag.selftest.bj")!
        let mode = AppVoiceOverMode(store: store)
        mode.isEnabled = true       // exercise the adaptive-pacing / channel-quiet path
        let model = BlackjackTableViewModel(seed: 4242, fastMode: true,
                                            audio: AudioEngine(configureSession: false),
                                            mode: mode, rules: .riverwood, returnLabel: "x")
        let run = Task { await model.run() }
        var ticks = 0, decisions = 0
        while ticks < 3000, decisions < target, model.outcome == nil {
            if model.betBox != nil {
                model.confirmBet()
            } else if let turn = model.turn {
                decisions += 1
                if turn.legal.allowed.contains(.hit), turn.total < 17 { model.hit() } else { model.stand() }
            }
            try? await Task.sleep(nanoseconds: 4_000_000)
            ticks += 1
        }
        run.cancel()
        line("blackjack decisions: \(decisions)")
    }

    private static func driveTexas(decisions target: Int) async {
        line("--- texas ---")
        let store = UserDefaults(suiteName: "diag.selftest.texas")!
        let mode = AppVoiceOverMode(store: store)
        mode.isEnabled = true
        let model = TableViewModel(seed: 20260811, fastMode: true,
                                   audio: AudioEngine(configureSession: false),
                                   mode: mode, rules: .classic, returnLabel: "x")
        let run = Task { await model.run() }
        var ticks = 0, decisions = 0
        while ticks < 3000, decisions < target, model.outcome == nil {
            if model.humanTurn != nil { decisions += 1; model.checkOrCall() }
            try? await Task.sleep(nanoseconds: 4_000_000)
            ticks += 1
        }
        run.cancel()
        line("texas decisions: \(decisions)")
    }

    // MARK: - Read the trace back and prove it captured

    private static func summarize(_ url: URL?) {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            line("FAIL: no trace file to read back"); return
        }
        let lines = text.split(separator: "\n").map(String.init)
        line("records written: \(lines.count)")

        var histogram: [String: Int] = [:]
        var sampleSpoken: [String] = []
        for raw in lines {
            guard let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let kind = obj["k"] as? String else { continue }
            histogram[kind, default: 0] += 1
            // A few real spoken lines, to prove text (not keys) is captured.
            if sampleSpoken.count < 6, kind == "q.speak.start", let t = obj["text"] as? String {
                sampleSpoken.append(t)
            }
        }
        line("── record kinds ──")
        for key in histogram.keys.sorted() { line("  \(key): \(histogram[key]!)") }
        line("── sample spoken text ──")
        for s in sampleSpoken { line("  “\(s)”") }

        // A blunt pass/fail the console makes obvious.
        let required = ["session.begin", "ui.present", "ui.suspend", "ui.action",
                        "c.say", "q.enqueue", "q.speak.start", "a.play"]
        let missing = required.filter { (histogram[$0] ?? 0) == 0 }
        line(missing.isEmpty ? "PASS: all core record kinds captured"
                             : "FAIL: missing record kinds: \(missing.joined(separator: ", "))")
    }
}
