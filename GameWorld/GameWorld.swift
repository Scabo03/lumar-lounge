// GameWorld
// =====================================================================
// The world that surrounds the tables: the player and their state,
// chips and tokens, NPCs, and progression across casinos.
//
// RULE: may import GameEngine. Must NOT import UI nor Audio (nor any
// SwiftUI/UIKit). The dependency direction is UI → GameWorld → GameEngine.
//
// First real content (M1.4): the multi-hand session driver — see
// SessionDriver.swift, ActionProvider.swift, SessionTypes.swift and README.md.

import Foundation
import GameEngine

/// Namespace and metadata for the game-world layer.
public enum GameWorld {
    /// Semantic version of the game-world layer.
    public static let version = "0.1.0"

    /// The version of the rules engine this world layer is built against.
    /// Present only to prove the GameWorld → GameEngine dependency compiles.
    public static let engineVersion = GameEngine.version
}
