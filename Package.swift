// swift-tools-version: 5.9
import PackageDescription

// LumarKit groups the four "pure logic" layers of Lumar Lounge as separate
// Swift modules. SwiftPM enforces the dependency direction at compile time:
//
//     UI ──▶ GameWorld ──▶ GameEngine
//     │                        ▲
//     └──▶ Audio               │
//                              (Audio is cross-cutting, knows nothing of games)
//
// A module can only `import` another module that is declared as its dependency
// below. Importing in the wrong direction (e.g. GameWorld importing UI) simply
// fails to build, so the architectural rule is mechanically guaranteed.
let package = Package(
    name: "LumarKit",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "GameEngine", targets: ["GameEngine"]),
        .library(name: "GameWorld", targets: ["GameWorld"]),
        .library(name: "Audio", targets: ["Audio"]),
        .library(name: "UI", targets: ["UI"]),
    ],
    targets: [
        // Pure rules engine. Foundation only, no Apple UI/Audio frameworks.
        .target(
            name: "GameEngine",
            path: "GameEngine"
        ),
        // The world around the tables: player, chips, NPCs, progression.
        // May use GameEngine, never UI nor Audio.
        .target(
            name: "GameWorld",
            dependencies: ["GameEngine"],
            path: "GameWorld"
        ),
        // Cross-cutting sound & haptics. Generic, game-agnostic.
        .target(
            name: "Audio",
            path: "Audio"
        ),
        // All SwiftUI views. May use everything below it in the graph.
        .target(
            name: "UI",
            dependencies: ["GameWorld", "GameEngine", "Audio"],
            path: "UI"
        ),
    ]
)
