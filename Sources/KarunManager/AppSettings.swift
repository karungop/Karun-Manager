import AppKit
import KarunManagerCore
import Observation
import ServiceManagement

/// User-adjustable behaviour, persisted in UserDefaults. (Skip threshold, categories and skip
/// directions live in `TaskStore`, next to the rules that use them.)
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let nudgeInterval = "settings.nudgeIntervalMinutes"
        static let idleThreshold = "settings.idleThresholdMinutes"
        static let reminderHour = "settings.dueReminderHour"
        static let blocklist = "settings.focusApps"
        static let hotkey = "settings.quickCaptureHotkey"
        static let quietDuringVideo = "settings.quietDuringVideo"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Minutes between idle nudges.
    var nudgeIntervalMinutes: Int { didSet { defaults.set(nudgeIntervalMinutes, forKey: Key.nudgeInterval) } }
    /// Minutes without keyboard/mouse input before an idle nudge may appear.
    var idleThresholdMinutes: Int { didSet { defaults.set(idleThresholdMinutes, forKey: Key.idleThreshold) } }
    /// Hour of day (0–23) for "due today" reminders.
    var dueReminderHour: Int { didSet { defaults.set(dueReminderHour, forKey: Key.reminderHour) } }
    /// Distraction Guard: bundle IDs where idle nudges become a badge + notification instead of a HUD.
    var focusApps: [String] { didSet { defaults.set(focusApps, forKey: Key.blocklist) } }
    /// Global shortcut for Quick Capture.
    var quickCaptureHotkey: QuickCaptureHotkey { didSet { defaults.set(quickCaptureHotkey.rawValue, forKey: Key.hotkey) } }
    /// Hold nudges while a video plays or the front app is full screen.
    var quietDuringVideo: Bool { didSet { defaults.set(quietDuringVideo, forKey: Key.quietDuringVideo) } }
    /// Set by the app when another app already owns the chosen shortcut.
    var quickCaptureHotkeyTaken = false

    private(set) var launchAtLoginStatus: SMAppService.Status = SMAppService.mainApp.status
    /// Why macOS refused the last Open-at-login change, shown under the switch.
    private(set) var launchAtLoginError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.nudgeInterval: 10,
            Key.idleThreshold: 2,
            Key.reminderHour: 9,
            Key.blocklist: NudgePolicy.defaultBlocklist.sorted(),
            Key.quietDuringVideo: true,
        ])
        nudgeIntervalMinutes = defaults.integer(forKey: Key.nudgeInterval)
        idleThresholdMinutes = defaults.integer(forKey: Key.idleThreshold)
        dueReminderHour = defaults.integer(forKey: Key.reminderHour)
        focusApps = defaults.stringArray(forKey: Key.blocklist) ?? []
        quietDuringVideo = defaults.bool(forKey: Key.quietDuringVideo)
        quickCaptureHotkey = defaults.string(forKey: Key.hotkey).flatMap(QuickCaptureHotkey.init(rawValue:)) ?? .optionSpace
    }

    /// Re-reads every setting from UserDefaults (after iCloud brings in changes from another Mac).
    /// Assigning only changed values keeps the didSet write-backs and observers quiet otherwise.
    func reload() {
        func update<T: Equatable>(_ path: ReferenceWritableKeyPath<AppSettings, T>, _ value: T) {
            if self[keyPath: path] != value { self[keyPath: path] = value }
        }
        update(\.nudgeIntervalMinutes, defaults.integer(forKey: Key.nudgeInterval))
        update(\.idleThresholdMinutes, defaults.integer(forKey: Key.idleThreshold))
        update(\.dueReminderHour, defaults.integer(forKey: Key.reminderHour))
        update(\.focusApps, defaults.stringArray(forKey: Key.blocklist) ?? [])
        update(\.quietDuringVideo, defaults.bool(forKey: Key.quietDuringVideo))
        update(\.quickCaptureHotkey, defaults.string(forKey: Key.hotkey).flatMap(QuickCaptureHotkey.init(rawValue:)) ?? .optionSpace)
    }

    var nudgePolicy: NudgePolicy {
        NudgePolicy(
            nudgeInterval: TimeInterval(nudgeIntervalMinutes * 60),
            idleThreshold: TimeInterval(idleThresholdMinutes * 60),
            blocklist: Set(focusApps)
        )
    }

    // MARK: Launch at login

    var launchesAtLogin: Bool {
        launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
    }

    /// Returns an error message if macOS refused.
    @discardableResult
    func setLaunchesAtLogin(_ enabled: Bool) -> String? {
        defer { launchAtLoginStatus = SMAppService.mainApp.status }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
            return nil
        } catch {
            NSLog("KarunManager: launch at login change failed: \(error)")
            launchAtLoginError = error.localizedDescription
            return launchAtLoginError
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = SMAppService.mainApp.status
    }
}
