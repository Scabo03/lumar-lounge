// SpokenChannelPacing.swift
// =====================================================================
// The adaptive-pacing safeguard (D-056). With the app's VoiceOver mode ON the UI
// advances the visual timeline only when the spoken channel (croupier + the
// announcement queue) is quiet, so eye and ear walk together (D-034). But that
// wait must NEVER be unbounded: if a spoken item fails to signal completion — a
// croupier mp3 whose finish callback is lost on device, a queue item awaiting a
// notification that never arrives — the UI would freeze, and a later tap could
// then release a pile-up of collapsed events onto the wrong turn (the pre-flop
// block seen on device).
//
// So the wait has a cumulative SAFEGUARD: after `maxWait` the UI proceeds anyway
// (a brief overlap of one announcement onto the next is far better than a frozen
// UI that steals the player's choice). Real usability wins over perfect synthesis.
// The AudioEngine's completion guarantee (D-056) makes tripping this rare; this is
// the backstop. Pure and game-agnostic, so both tables and any future game reuse
// it, and it is directly unit-testable with a controllable `isQuiet` closure.

import Foundation
import Audio

@MainActor
enum SpokenChannelPacing {

    /// After this long the UI proceeds even if the spoken channel hasn't gone quiet.
    /// This is a HANG BACKSTOP, not a normal-speech budget: it must sit ABOVE the
    /// longest normal per-event spoken time so it never trips during real narration.
    /// Raised to 8 s when the real (longer, more verbose) Skypool croupier voices
    /// landed (D-068): a full croupier line + its content synthesis can run ~5–6 s, and
    /// the previous 3 s cap fired systematically mid-speech in VoiceOver-ON adaptive
    /// mode, desyncing eye and ear. A genuine hang is caught far sooner by the
    /// AudioEngine's per-clip completion timeout (duration + margin, D-056) and the
    /// announcement queue's own cap, so this only fires if BOTH of those also fail.
    /// (VoiceOver-OFF mode never uses this path — it keeps its fixed human pauses.)
    static let defaultMaxWait: TimeInterval = 8.0
    /// The HARD ceiling for an adaptive wait: however much speech the channel still
    /// claims to owe, the UI never blocks longer than this (D-085).
    /// Measured on device (D-085): a fully preserved three-way showdown — every hand
    /// revealed, nothing dropped — costs 21.7 s of spoken channel. The ceiling sits
    /// above it so that legitimate narration is waited out in full; a genuine hang is
    /// still caught in `minimumWait`, because a hung channel reports nothing outstanding.
    static let hardCeiling: TimeInterval = 25.0
    /// The floor for an adaptive wait, so a channel that reports nothing outstanding
    /// still gets a moment to settle.
    static let minimumWait: TimeInterval = 2.0

    /// The wait to allow given how much speech the channel says it still owes.
    ///
    /// A FIXED cap cannot be right for both jobs (measured, D-085): a three-way
    /// showdown legitimately needs ~18 s of narration, so an 8 s cap fired in the
    /// MIDDLE of honest speech and let the display run away from the ear; but raising
    /// the cap to cover it would leave a genuine hang frozen for that long. Sizing the
    /// wait on the channel's own estimate separates the two: real narration is waited
    /// out (estimate is large), while a hang — nothing outstanding yet never quiet —
    /// trips in `minimumWait`.
    static func adaptiveMaxWait(channelRemaining: TimeInterval) -> TimeInterval {
        min(hardCeiling, max(minimumWait, channelRemaining * 1.4 + 1.0))
    }
    /// Polling granularity while waiting.
    static let defaultStep: TimeInterval = 0.025

    /// Waits until `isQuiet()` is true, then returns `true`. Returns `false` (without
    /// waiting further) if `isCancelled()` becomes true, or if `maxWait` elapses first
    /// — the safeguard, logged so a device trace shows it tripping.
    @discardableResult
    static func awaitQuiet(isQuiet: () -> Bool,
                           isCancelled: () -> Bool = { false },
                           maxWait: TimeInterval = defaultMaxWait,
                           step: TimeInterval = defaultStep,
                           label: String = "") async -> Bool {
        var waited: TimeInterval = 0
        while !isQuiet() {
            if isCancelled() { return false }
            if waited >= maxWait {
                SpokenLog.log("visual SAFEGUARD \(label) proceeding after \(String(format: "%.2f", waited))s (channel not quiet)")
                return false
            }
            try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            waited += step
        }
        return true
    }
}
