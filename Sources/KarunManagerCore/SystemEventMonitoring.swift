import AppKit
import CoreGraphics

/// Wraps the macOS system queries the scheduler depends on so they can be mocked (spec §4B).
@MainActor
public protocol SystemEventMonitoring: AnyObject {
    /// Seconds since the last keyboard/mouse input anywhere in the session.
    var systemIdleTime: TimeInterval { get }
    var frontmostBundleIdentifier: String? { get }
    func startObservingWake(_ handler: @escaping @MainActor () -> Void)
    func stopObservingWake()
}

@MainActor
public final class LiveSystemEventMonitor: SystemEventMonitoring {
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    public init() {}

    public var systemIdleTime: TimeInterval {
        // kCGAnyInputEventType (~0) isn't a named Swift case; it covers every user input event.
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    public var frontmostBundleIdentifier: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    public func startObservingWake(_ handler: @escaping @MainActor () -> Void) {
        stopObservingWake()
        let sources: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")),
        ]
        for (center, name) in sources {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            }
            observers.append((center, token))
        }
    }

    public func stopObservingWake() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }
}

/// Test/CLI double: set idle time and frontmost app directly, fire wake on demand.
@MainActor
public final class MockSystemEventMonitor: SystemEventMonitoring {
    public var systemIdleTime: TimeInterval
    public var frontmostBundleIdentifier: String?
    private var wakeHandler: (@MainActor () -> Void)?

    public init(systemIdleTime: TimeInterval = 0, frontmostBundleIdentifier: String? = nil) {
        self.systemIdleTime = systemIdleTime
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
    }

    public func startObservingWake(_ handler: @escaping @MainActor () -> Void) { wakeHandler = handler }
    public func stopObservingWake() { wakeHandler = nil }
    public func simulateWake() { wakeHandler?() }
}
