// PacingBench.swift
// =====================================================================
// AN ON-DEVICE MEASUREMENT HARNESS for the spoken/visual/audio channel timing
// (D-085). Launched with `-pacingBench`, it runs against the REAL AudioEngine and
// the REAL bundled mp3s and prints its numbers to stdout, so a device console
// capture gives hard timings instead of simulator guesses.
//
// Why it must run on device (D-056's lesson): on the simulator every AVAudioPlayer
// completion arrives promptly and clip latency is different; the freeze this whole
// investigation is about only exists where the completions are late or lost.
//
// It measures, in order:
//   1. Per-clip play→completion latency for the real croupier voices.
//   2. The estimate error of `AnnouncementQueue.speakTime` against the real
//      Italian synthesiser (the drop/cap heuristic rests on it).
//   3. The COMBINED spoken-channel backlog through a realistic showdown burst,
//      driven through the real SpeechConductor + AnnouncementQueue.
//   4. How often the adaptive-pacing safeguard would trip during that burst.

import Foundation
import Audio
#if canImport(UIKit)
import UIKit
#endif
import AVFoundation

@MainActor
public enum PacingBench {

    public static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-pacingBench")
    }

    private static func line(_ s: String) {
        print("BENCH \(s)")
        fflush(stdout)
    }

    public static func run() async {
        line("=== LUMAR PACING BENCH ===")
        #if canImport(UIKit)
        line("voiceOverRunning=\(UIAccessibility.isVoiceOverRunning)")
        #endif
        let audio = AudioEngine()
        await clipLatency(audio)
        await speakTimeAccuracy()
        await channelBacklog(audio)
        line("=== END ===")
    }

    // MARK: - 1. Per-clip completion latency (the D-056 failure mode)

    private static func clipLatency(_ audio: AudioEngine) async {
        line("--- clip latency (play → completion) ---")
        let clips: [SoundID] = [
            SoundCatalog.voHandStart, SoundCatalog.voYourTurn, SoundCatalog.voShowdown,
            SoundCatalog.voPotAwarded, SoundCatalog.voFlop, SoundCatalog.voTurn,
            SoundCatalog.voRiver, SoundCatalog.voTowerShowdown, SoundCatalog.voTowerPotAwarded,
        ]
        for clip in clips {
            guard audio.isAvailable(clip) else { line("\(clip.rawValue): NOT BUNDLED"); continue }
            let nominal = audio.duration(of: clip) ?? -1
            let t0 = Date()
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                audio.play(clip, category: .croupier) { c.resume() }
            }
            let elapsed = Date().timeIntervalSince(t0)
            line(String(format: "%@: nominal %.3fs, completion %.3fs, overhead %+.3fs",
                        clip.rawValue, nominal, elapsed, elapsed - nominal))
        }
    }

    // MARK: - 2. Is speakTime() a good estimate of the real synthesiser?

    private static func speakTimeAccuracy() async {
        line("--- speakTime estimate vs real synthesis ---")
        let samples = [
            "è il tuo turno",
            "giocatore 2 rilancia a 400",
            "hai vinto con doppia coppia, kicker donna",
            "giocatore 3: colore all'asso",
            "il Professore, re di cuori, dieci di picche",
            "pareggio tra giocatore 2 e giocatore 3, entrambi coppia di assi, kicker donna",
        ]
        for text in samples {
            let estimate = AnnouncementQueue.speakTime(text)
            let real = await measureSynthesis(text)
            line(String(format: "est %.2fs real %.2fs err %+.0f%%  \"%@\"",
                        estimate, real, (estimate - real) / max(0.01, real) * 100, text))
        }
    }

    /// Speaks the line for real and times it end to end. `write(_:)` returns empty
    /// buffers on device in this context, so the honest measurement is to SPEAK it.
    private static func measureSynthesis(_ text: String) async -> TimeInterval {
        let delegate = SpeechTimer()
        return await withCheckedContinuation { (cont: CheckedContinuation<TimeInterval, Never>) in
            let synth = AVSpeechSynthesizer()
            synth.delegate = delegate
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "it-IT")
            let start = Date()
            var resumed = false
            let finish: (TimeInterval) -> Void = { value in
                guard !resumed else { return }
                resumed = true
                _ = synth              // keep alive until it has spoken
                cont.resume(returning: value)
            }
            delegate.onFinish = { finish(Date().timeIntervalSince(start)) }
            synth.speak(utterance)
            // Safeguard: every continuation waiting on an external callback gets a
            // timeout, always (the rule this whole session enforces).
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { finish(-1) }
        }
    }

    private final class SpeechTimer: NSObject, AVSpeechSynthesizerDelegate {
        var onFinish: (() -> Void)?
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { onFinish?() }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { onFinish?() }
    }

    // MARK: - 3. Combined channel backlog through a showdown burst

    private static func channelBacklog(_ audio: AudioEngine) async {
        line("--- spoken-channel backlog through a showdown burst ---")
        let queue = AnnouncementQueue()
        queue.voiceOverOverride = true      // measure the VoiceOver-ON path
        queue.pacedWhenSilent = true        // simulate speaking time when nobody listens
        let conductor = SpeechConductor(audio: audio, queue: queue)
        conductor.handBegan()

        // A realistic three-way showdown, fired back to back the way the driver emits
        // it (the producer runs at code speed — that is by design, D-015).
        let burst: [(SoundID?, String?, AnnouncementPriority)] = [
            // Real app priorities (SpeechMap): a revealed hand is HIGH — the budget may
            // drop chatter, never the result of the hand (D-085).
            (SoundCatalog.voShowdown, "giocatore 1: coppia di re, kicker asso", .high),
            (SoundCatalog.voShowdown, "giocatore 2: doppia coppia, assi e dieci, kicker donna", .high),
            (SoundCatalog.voShowdown, "giocatore 3: colore all'asso", .high),
            (SoundCatalog.voPotAwarded, "hai vinto con doppia coppia, kicker donna", .high),
        ]
        let start = Date()
        for (lead, synth, prio) in burst {
            conductor.say(lead: lead, synthesis: synth, priority: prio, reason: "bench")
        }
        line(String(format: "enqueued %d items in %.3fs (producer speed)",
                    burst.count, Date().timeIntervalSince(start)))

        // Sample the channel until it goes quiet, reporting how long the ear stays
        // behind the game state.
        var samples = 0
        let t0 = Date()
        while !(conductor.isIdle && queue.isQuiet), Date().timeIntervalSince(t0) < 30 {
            if samples % 20 == 0 {
                line(String(format: "  t=%.2fs conductorIdle=%@ queueQuiet=%@ queuePending=%d",
                            Date().timeIntervalSince(t0),
                            conductor.isIdle ? "Y" : "N", queue.isQuiet ? "Y" : "N",
                            queue.pendingSnapshot().count))
            }
            samples += 1
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let drained = Date().timeIntervalSince(t0)
        line(String(format: "channel drained after %.2fs — THIS IS HOW FAR THE EAR LAGS THE GAME", drained))
        line(String(format: "fixed 8s cap would trip: %@   adaptive cap would be %.1fs",
                    drained > 8 ? "YES" : "no",
                    SpokenChannelPacing.adaptiveMaxWait(channelRemaining: drained)))

        // And now the case the budget EXISTS for: rapid opponent chatter, which carries
        // far less information than a showdown and must not be allowed to pile up.
        line("--- chatter burst (10 rapid opponent actions) ---")
        let queue2 = AnnouncementQueue()
        queue2.voiceOverOverride = true
        queue2.pacedWhenSilent = true
        let conductor2 = SpeechConductor(audio: audio, queue: queue2)
        conductor2.handBegan()
        var dropped = 0
        conductor2.dropObserver = { _, _ in dropped += 1 }
        for i in 1...10 {
            conductor2.say(lead: nil, synthesis: "giocatore \(i % 3 + 1) rilancia a \(i * 100)",
                           priority: .medium, reason: "chatter")
        }
        line(String(format: "10 chatter lines: channel owes %.1fs, dropped %d (budget %.1fs)",
                    conductor2.channelRemaining, dropped, SpeechConductor.channelBudget))
        let t1 = Date()
        while !(conductor2.isIdle && queue2.isQuiet), Date().timeIntervalSince(t1) < 30 {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        line(String(format: "chatter drained after %.2fs", Date().timeIntervalSince(t1)))
    }
}
