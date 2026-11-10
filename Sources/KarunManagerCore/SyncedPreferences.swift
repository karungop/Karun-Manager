import Foundation

/// The parts of `NSUbiquitousKeyValueStore` that `SyncedPreferences` uses, so tests can supply a fake.
public protocol UbiquitousKeyValueStoring: AnyObject {
    var dictionaryRepresentation: [String: Any] { get }
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: UbiquitousKeyValueStoring {}

/// Mirrors chosen UserDefaults keys to iCloud's key-value store, so preferences (categories, skip
/// rules, nudge timing) follow the user to their other devices. UserDefaults stays the source the app
/// reads; this keeps it and iCloud in step in both directions.
///
/// On `start()`, values already in iCloud win (a new Mac adopts your settings) and local-only keys are
/// uploaded. After that, local edits go up and remote edits come down; `onRemoteChange` fires after
/// remote values have been written to UserDefaults so the app can refresh.
@MainActor
public final class SyncedPreferences {
    /// Keys synced by default: everything that describes how you manage tasks. Per-machine choices
    /// (the Quick Capture shortcut, launch at login, notification permissions) stay local.
    public static let defaultKeys: Set<String> = [
        "categories",
        "skipThreshold",
        "settings.nudgeIntervalMinutes",
        "settings.idleThresholdMinutes",
        "settings.dueReminderHour",
        "settings.focusApps",
        "settings.quietDuringVideo",
    ]
    /// Key prefixes synced by default (one skip-direction key per category).
    public static let defaultPrefixes = ["skipDirection."]

    public var onRemoteChange: () -> Void = {}

    private let defaults: UserDefaults
    private let domain: String
    private let cloud: UbiquitousKeyValueStoring
    private let keys: Set<String>
    private let prefixes: [String]
    private var isApplyingRemote = false
    private var observers: [NSObjectProtocol] = []

    /// `domain` names the defaults' persistent domain: the bundle identifier for `.standard`, else the suite name.
    public init(
        defaults: UserDefaults,
        domain: String,
        cloud: UbiquitousKeyValueStoring = NSUbiquitousKeyValueStore.default,
        keys: Set<String> = SyncedPreferences.defaultKeys,
        prefixes: [String] = SyncedPreferences.defaultPrefixes
    ) {
        self.defaults = defaults
        self.domain = domain
        self.cloud = cloud
        self.keys = keys
        self.prefixes = prefixes
    }

    public func isSynced(_ key: String) -> Bool {
        keys.contains(key) || prefixes.contains { key.hasPrefix($0) }
    }

    /// Reconciles once, then follows changes. The live notifications are only observed for the real
    /// iCloud store; tests drive `pushLocalChanges()` / `applyRemoteChange(keys:)` directly.
    public func start() {
        cloud.synchronize()
        applyRemoteChange(keys: nil, notify: false)
        let localOnly = syncedLocalKeys().subtracting(cloud.dictionaryRepresentation.keys)
        for key in localOnly { cloud.set(defaults.object(forKey: key), forKey: key) }

        guard let store = cloud as? NSUbiquitousKeyValueStore else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
        ) { [weak self] note in
            let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            MainActor.assumeIsolated { self?.applyRemoteChange(keys: changed) }
        })
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushLocalChanges() }
        })
    }

    /// Copies synced keys that differ from iCloud up to it, including removals (a deleted category's
    /// skip direction).
    public func pushLocalChanges() {
        guard !isApplyingRemote else { return }
        let local = syncedLocalKeys()
        for key in local {
            let value = defaults.object(forKey: key)
            if !Self.equal(value, cloud.object(forKey: key)) { cloud.set(value, forKey: key) }
        }
        for key in cloud.dictionaryRepresentation.keys where isSynced(key) && !local.contains(key) {
            cloud.removeObject(forKey: key)
        }
    }

    /// Writes iCloud's values for `keys` (nil: every synced key in iCloud) into UserDefaults.
    public func applyRemoteChange(keys changed: [String]?, notify: Bool = true) {
        let remote = cloud.dictionaryRepresentation
        let candidates = changed ?? Array(remote.keys)
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        var didChange = false
        for key in candidates where isSynced(key) {
            let value = remote[key]
            guard !Self.equal(value, defaults.object(forKey: key)) else { continue }
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            didChange = true
        }
        if didChange && notify { onRemoteChange() }
    }

    /// Keys actually stored in this defaults domain (registered defaults don't count, so a machine that
    /// never changed a setting doesn't overwrite one that did).
    private func syncedLocalKeys() -> Set<String> {
        let stored = defaults.persistentDomain(forName: domain) ?? [:]
        return Set(stored.keys.filter(isSynced))
    }

    private static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (l as NSObject, r as NSObject): l.isEqual(r)
        default: false
        }
    }
}
