// GameEngine
// =====================================================================
// Pure-Swift rules engine for card games and casino games.
//
// HARD RULE: this module must depend on Foundation ONLY. It must never
// import SwiftUI, UIKit, AVFoundation, CoreHaptics, Combine, or any other
// Apple framework that ties it to a single platform. It must stay
// self-contained and theoretically portable to other platforms.
//
// No game logic is implemented yet — this is scaffolding only.

import Foundation

/// Namespace and metadata for the rules engine layer.
public enum GameEngine {
    /// Semantic version of the rules engine layer.
    public static let version = "0.1.0"
}
