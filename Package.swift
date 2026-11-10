// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KarunManager",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "KarunManager", targets: ["KarunManager"]),
        // Shared with the iPhone app (iOS/KarunManagerMobile.xcodeproj).
        .library(name: "KarunManagerCore", targets: ["KarunManagerCore"]),
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
