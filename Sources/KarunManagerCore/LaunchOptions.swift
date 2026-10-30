import Foundation

public struct LaunchOptions: Equatable, Sendable {
    /// Swap in `MockSystemEventMonitor` and fire a wake event shortly after launch.
    public var simulateWake = false
    /// Swap in `MockSystemEventMonitor` reporting a long idle time and run an idle check immediately.
    public var simulateIdle = false
    /// Like `simulateIdle`, but with a Distraction Guard app (Terminal) frontmost: badge + notification, no HUD.
    public var simulateFocus = false
    /// Use a throwaway in-memory store (handy alongside the simulate flags).
    public var inMemory = false
    /// In-memory store pre-filled with sample tasks, for UI work and screenshots.
    public var demo = false
    /// Debug builds: render the window and HUDs to PNGs in this directory, then quit.
    public var snapshotDirectory: String?
    /// Log every idle check (time, idle seconds, decision) to stderr, to diagnose missed nudges.
    public var logNudges = false

    public var usesMockMonitor: Bool { simulateWake || simulateIdle || simulateFocus }

    public init(arguments: [String]) {
        let flags = Set(arguments.dropFirst())
        simulateWake = flags.contains("--simulate-wake")
        simulateFocus = flags.contains("--simulate-focus")
        simulateIdle = flags.contains("--simulate-idle") || simulateFocus
        demo = flags.contains("--demo")
        logNudges = flags.contains("--log-nudges")
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
            snapshotDirectory = arguments[index + 1]
        }
        inMemory = flags.contains("--in-memory") || demo
    }
}
