// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KarunManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KarunManager", targets: ["KarunManager"]),
    ],
    targets: [
        // Pure domain logic: model, MLFQ engine, nudge policy, system-event abstraction.
        .target(name: "KarunManagerCore"),
        // AppKit/SwiftUI shell: status item, HUD panels, hotkey, wiring.
        .executableTarget(
            name: "KarunManager",
            dependencies: ["KarunManagerCore"]
        ),
        .testTarget(
            name: "KarunManagerCoreTests",
            dependencies: ["KarunManagerCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
