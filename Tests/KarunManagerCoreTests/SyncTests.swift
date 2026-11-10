import Foundation
import SwiftData
import Testing
@testable import KarunManagerCore

private final class FakeCloudStore: UbiquitousKeyValueStoring {
    var values: [String: Any] = [:]
    var dictionaryRepresentation: [String: Any] { values }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    func synchronize() -> Bool { true }
}

@MainActor
struct SyncTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "SyncTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func makeStore(now: @escaping () -> Date = { Date() }) throws -> TaskStore {
        TaskStore(container: try TaskStore.makeContainer(inMemory: true), defaults: makeDefaults().0, now: now)
    }

    // MARK: Task conflicts

    @Test func duplicateIDsKeepTheMostRecentlyTouchedCopy() throws {
        let store = try makeStore()
        let id = UUID()
        let base = Date(timeIntervalSince1970: 1_000)
        let stale = TaskItem(id: id, title: "Stale", createdAt: base)
        let fresh = TaskItem(id: id, title: "Fresh", createdAt: base)
        fresh.enqueuedAt = base.addingTimeInterval(60)
        store.context.insert(stale)
        store.context.insert(fresh)
        try store.add(title: "Unrelated")

        #expect(try store.repairSyncConflicts() == 1)
        let titles = try store.allTasks().map(\.title).sorted()
        #expect(titles == ["Fresh", "Unrelated"])
    }

    @Test func twoDevicesCompletingARepeatLeaveOneNextOccurrence() throws {
        let store = try makeStore()
        let task = try store.add(title: "Water plants", repeatRule: .daily)
        let next = try #require(try store.complete(task))
        // The other Mac scheduled its own next occurrence for the same series.
        let twin = TaskItem(title: "Water plants", repeatRule: .daily, availableFrom: next.availableFrom)
        twin.seriesID = task.seriesID
        store.context.insert(twin)

        #expect(try store.repairSyncConflicts() == 1)
        #expect(try store.unfinishedOccurrences(inSeries: try #require(task.seriesID)).count == 1)
    }

    @Test func modelHasCloudKitCompatibleDefaults() throws {
        // CloudKit rejects schemas with unique constraints or non-optional properties lacking defaults;
        // a record arriving without fields must still decode.
        let task = TaskItem(title: "x")
        #expect(task.queueLevel == QueueLevel.medium.rawValue)
        let store = try makeStore()
        store.context.insert(task)
        store.context.insert(TaskItem(id: task.id, title: "same id"))
        try store.context.save()  // would throw with @Attribute(.unique)
    }

    // MARK: Preferences

    @Test func startAdoptsCloudValuesAndUploadsLocalOnlyKeys() {
        let (defaults, suite) = makeDefaults()
        defaults.set(8, forKey: "skipThreshold")
        defaults.set("demote", forKey: "skipDirection.Work")
        defaults.set("cmdShiftSpace", forKey: "settings.quickCaptureHotkey")  // per-Mac, never synced
        let cloud = FakeCloudStore()
        cloud.values["skipThreshold"] = 3
        cloud.values["categories"] = ["Work", "Home"]

        let prefs = SyncedPreferences(defaults: defaults, domain: suite, cloud: cloud)
        prefs.start()

        #expect(defaults.integer(forKey: "skipThreshold") == 3)
        #expect(defaults.stringArray(forKey: "categories") == ["Work", "Home"])
        #expect(cloud.values["skipDirection.Work"] as? String == "demote")
        #expect(cloud.values["settings.quickCaptureHotkey"] == nil)
    }

    @Test func registeredDefaultsAreNotUploaded() {
        let (defaults, suite) = makeDefaults()
        defaults.register(defaults: ["settings.nudgeIntervalMinutes": 10])
        let cloud = FakeCloudStore()
        SyncedPreferences(defaults: defaults, domain: suite, cloud: cloud).start()
        #expect(cloud.values.isEmpty)
    }

    @Test func localEditsAndRemovalsArePushed() {
        let (defaults, suite) = makeDefaults()
        let cloud = FakeCloudStore()
        cloud.values["skipDirection.Old"] = "demote"
        let prefs = SyncedPreferences(defaults: defaults, domain: suite, cloud: cloud)
        prefs.start()
        #expect(defaults.string(forKey: "skipDirection.Old") == "demote")

        defaults.removeObject(forKey: "skipDirection.Old")
        defaults.set(["A"], forKey: "categories")
        prefs.pushLocalChanges()

        #expect(cloud.values["skipDirection.Old"] == nil)
        #expect(cloud.values["categories"] as? [String] == ["A"])
    }

    @Test func remoteChangesNotifyOnlyWhenSomethingChanged() {
        let (defaults, suite) = makeDefaults()
        let cloud = FakeCloudStore()
        let prefs = SyncedPreferences(defaults: defaults, domain: suite, cloud: cloud)
        var notified = 0
        prefs.onRemoteChange = { notified += 1 }
        prefs.start()

        cloud.values["skipThreshold"] = 6
        prefs.applyRemoteChange(keys: ["skipThreshold"])
        prefs.applyRemoteChange(keys: ["skipThreshold"])  // same value again
        #expect(defaults.integer(forKey: "skipThreshold") == 6)
        #expect(notified == 1)

        cloud.values["skipThreshold"] = nil
        prefs.applyRemoteChange(keys: ["skipThreshold"])
        #expect(defaults.object(forKey: "skipThreshold") == nil)
        #expect(notified == 2)
    }

    @Test func storeSettingsUseTheSyncedKeys() throws {
        // Guards against renaming a TaskStore key without updating SyncedPreferences.defaultKeys.
        let (defaults, suite) = makeDefaults()
        let store = TaskStore(container: try TaskStore.makeContainer(inMemory: true), defaults: defaults)
        store.setSkipThreshold(7)
        store.addCategory("Garden")
        store.setSkipDirection(.demote, for: "Garden")
        let stored = defaults.persistentDomain(forName: suite) ?? [:]
        let prefs = SyncedPreferences(defaults: defaults, domain: suite, cloud: FakeCloudStore())
        #expect(!stored.isEmpty)
        #expect(stored.keys.allSatisfy(prefs.isSynced))
    }
}
