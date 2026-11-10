import AppKit
import CoreGraphics
import IOKit.pwr_mgt

/// Wraps the macOS system queries the scheduler depends on so they can be mocked (spec §4B).
@MainActor
public protocol SystemEventMonitoring: AnyObject {
    /// Seconds since the last keyboard/mouse input anywhere in the session.
    var systemIdleTime: TimeInterval { get }
    var frontmostBundleIdentifier: String? { get }
    /// Why the user is probably watching something (a video is playing, or the front app is full
    /// screen), or nil. Nudges hold off while this is set.
    var watchingMediaReason: String? { get }
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

    public var watchingMediaReason: String? {
        if let player = Self.processKeepingDisplayAwake() { return "\(player) is keeping the display awake" }
        if let app = Self.fullScreenFrontmostApp() { return "\(app) is full screen" }
        return nil
    }

    /// Assertion types video playback takes so the screen doesn't dim mid-show (QuickTime, IINA, VLC,
    /// TV, and browsers while a video plays). Audio-only playback takes a weaker, system-sleep-only
    /// assertion, so music doesn't count.
    private static let displayAssertionTypes: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]
    /// Keep-awake tools hold display assertions without anyone watching anything.
    private static let ignoredAssertionOwners: Set<String> = ["caffeinate", "Amphetamine", "KeepingYouAwake"]

    /// Name of another process holding a display-sleep assertion, if any.
    static func processKeepingDisplayAwake() -> String? {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for (pid, assertions) in byProcess where pid.int32Value != ownPID {
            for assertion in assertions {
                guard let type = assertion["AssertType"] as? String, displayAssertionTypes.contains(type) else { continue }
                let owner = assertion["Process Name"] as? String ?? "pid \(pid)"
                if !ignoredAssertionOwners.contains(owner) { return owner }
            }
        }
        return nil
    }

    /// Name of the frontmost app if one of its windows covers a whole display (full screen, or a
    /// full-screen video player). Reading window bounds needs no Screen Recording permission.
    static func fullScreenFrontmostApp() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        // Window bounds are in top-left-origin coordinates; convert each screen's frame to match.
        let screenRects = NSScreen.screens.map { screen in
            CGRect(x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY,
                   width: screen.frame.width, height: screen.frame.height)
        }
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            if screenRects.contains(where: { $0.equalTo(bounds) }) {
                return app.localizedName ?? app.bundleIdentifier ?? "The front app"
            }
        }
        return nil
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
    public var watchingMediaReason: String?
    private var wakeHandler: (@MainActor () -> Void)?

    public init(
        systemIdleTime: TimeInterval = 0,
        frontmostBundleIdentifier: String? = nil,
        watchingMediaReason: String? = nil
    ) {
        self.systemIdleTime = systemIdleTime
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.watchingMediaReason = watchingMediaReason
    }

    public func startObservingWake(_ handler: @escaping @MainActor () -> Void) { wakeHandler = handler }
    public func stopObservingWake() { wakeHandler = nil }
    public func simulateWake() { wakeHandler?() }
}
