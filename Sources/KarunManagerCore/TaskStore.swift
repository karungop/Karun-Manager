import Foundation
import SwiftData

@MainActor
public final class TaskStore {
    /// Held strongly: a ModelContext does not keep its container alive.
    public let container: ModelContainer
    public let context: ModelContext
    private let now: () -> Date
    private let defaults: UserDefaults

    /// Per-category skip directions used until the user changes them.
    public static let defaultSkipDirections: [String: SkipDirection] = [
        TaskCategory.thingsToDo: .demote,
        TaskCategory.thingsToBuy: .stay,
        TaskCategory.peopleToCall: .stay,
    ]

    public init(
        container: ModelContainer,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.container = container
        self.context = container.mainContext
        self.defaults = defaults
        self.now = now
    }

    // MARK: Skip direction (a small per-category preference, so UserDefaults rather than SwiftData)

    public func skipDirection(for categoryName: String) -> SkipDirection {
        defaults.string(forKey: Self.skipDirectionKey(categoryName)).flatMap(SkipDirection.stored)
            ?? Self.defaultSkipDirections[categoryName]
            ?? .stay
    }

    public func setSkipDirection(_ direction: SkipDirection, for categoryName: String) {
        defaults.set(direction.rawValue, forKey: Self.skipDirectionKey(categoryName))
    }

    private static func skipDirectionKey(_ categoryName: String) -> String {
        "skipDirection.\(categoryName)"
    }

    // MARK: Skip threshold

    private static let skipThresholdKey = "skipThreshold"

    /// Skips before a task changes queue (2–20).
    public var skipThreshold: Int {
        let stored = defaults.integer(forKey: Self.skipThresholdKey)
        return stored == 0 ? MLFQ.defaultSkipThreshold : stored
    }

    public func setSkipThreshold(_ value: Int) {
        defaults.set(min(max(value, 2), 20), forKey: Self.skipThresholdKey)
    }

    // MARK: Categories (an ordered list in UserDefaults; tasks reference them by name)

    private static let categoriesKey = "categories"

    public var categories: [String] {
        let stored = defaults.stringArray(forKey: Self.categoriesKey) ?? []
        return stored.isEmpty ? TaskCategory.defaults : stored
    }

    /// Returns false for blank or duplicate (case-insensitive) names.
    @discardableResult
    public func addCategory(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !categories.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return false
        }
        defaults.set(categories + [trimmed], forKey: Self.categoriesKey)
        return true
    }

    /// Renames the category everywhere: the list, every task using it, and its skip-direction setting.
    @discardableResult
    public func renameCategory(_ old: String, to new: String) throws -> Bool {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old, categories.contains(old),
              !categories.contains(where: { $0 != old && $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return false
        }
        defaults.set(categories.map { $0 == old ? trimmed : $0 }, forKey: Self.categoriesKey)
        let direction = skipDirection(for: old)
        setSkipDirection(direction, for: trimmed)
        defaults.removeObject(forKey: Self.skipDirectionKey(old))
        for task in try tasks(inCategory: old) { task.categoryName = trimmed }
        try context.save()
        return true
    }

    /// Deletes a category, moving its tasks (open and completed) to `fallback`. The last category can't go.
    @discardableResult
    public func deleteCategory(_ name: String, movingTasksTo fallback: String) throws -> Bool {
        guard categories.count > 1, name != fallback, categories.contains(fallback) else { return false }
        defaults.set(categories.filter { $0 != name }, forKey: Self.categoriesKey)
        defaults.removeObject(forKey: Self.skipDirectionKey(name))
        for task in try tasks(inCategory: name) { task.categoryName = fallback }
        try context.save()
        return true
    }

    private func tasks(inCategory name: String) throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.categoryName == name }))
    }

    public static let storeDirectory = URL.applicationSupportDirectory
        .appending(path: "KarunManager", directoryHint: .isDirectory)

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([TaskItem.self])
        if inMemory {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let config = ModelConfiguration(url: storeDirectory.appending(path: "Tasks.store"))
        return try ModelContainer(for: schema, configurations: config)
    }

    /// Renames Tasks.store (and its -wal/-shm siblings) to "Tasks-damaged-<date>.store…" so a fresh store
    /// can be created without deleting anything.
    public static func moveStoreAside() {
        let fileManager = FileManager.default
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let names = (try? fileManager.contentsOfDirectory(atPath: storeDirectory.path)) ?? []
        for name in names where name.hasPrefix("Tasks.store") {
            let target = name.replacingOccurrences(of: "Tasks.store", with: "Tasks-damaged-\(stamp).store")
            try? fileManager.moveItem(at: storeDirectory.appending(path: name), to: storeDirectory.appending(path: target))
        }
    }

    @discardableResult
    public func add(
        title: String,
        categoryName: String = TaskCategory.thingsToDo,
        queueLevel: QueueLevel = .medium,
        repeatRule: RepeatRule = .never
    ) throws -> TaskItem {
        let task = TaskItem(
            title: title,
            categoryName: categoryName,
            queueLevel: queueLevel,
            createdAt: now(),
            repeatRule: repeatRule
        )
        context.insert(task)
        try context.save()
        return task
    }

    /// Sample data for `--demo`. Ages and skip counts are staggered so every UI state shows up.
    public func seedDemoData() throws {
        let samples: [(String, String, QueueLevel, Int, Bool)] = [
            ("Renew passport before the trip", TaskCategory.thingsToDo, .high, 2, false),
            ("Call Mom about Sunday dinner", TaskCategory.peopleToCall, .high, 0, false),
            ("Finish quarterly expense report", TaskCategory.thingsToDo, .medium, 4, false),
            ("Oat milk, coffee beans, lemons", TaskCategory.thingsToBuy, .medium, 1, false),
            ("Schedule dentist cleaning", TaskCategory.peopleToCall, .medium, 0, false),
            ("Water the plants", TaskCategory.thingsToDo, .medium, 0, false),
            ("Replace bike chain", TaskCategory.thingsToBuy, .low, 3, false),
            ("Read 'Designing Data-Intensive Applications'", TaskCategory.thingsToDo, .low, 0, false),
            ("Pay electricity bill", TaskCategory.thingsToDo, .medium, 0, true),
            ("Text Priya the photos", TaskCategory.peopleToCall, .low, 0, true),
        ]
        let start = now().addingTimeInterval(-86_400 * 6)
        for (index, sample) in samples.enumerated() {
            let task = TaskItem(
                title: sample.0,
                categoryName: sample.1,
                queueLevel: sample.2,
                skipCount: sample.3,
                createdAt: start.addingTimeInterval(Double(index) * 40_000),
                isCompleted: sample.4,
                completedAt: sample.4 ? now().addingTimeInterval(-Double(index) * 3_600) : nil
            )
            context.insert(task)
        }
        if let plants = try pendingTasks().first(where: { $0.title == "Water the plants" }) {
            plants.repeatRule = .weekly
            try complete(plants)
        }
        try context.save()
    }

    /// Every task (open and completed) in queue order.
    public func allTasks() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>()).sorted(by: MLFQ.isOrderedBefore)
    }

    /// Open tasks in queue order (the computed `queuePosition` can't go in a SortDescriptor).
    public func pendingTasks() throws -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isCompleted == false })
        return try context.fetch(descriptor).sorted(by: MLFQ.isOrderedBefore)
    }

    /// The task a nudge should show right now, skipping anything snoozed or scheduled for later.
    public func nextTask() throws -> TaskItem? {
        let current = now()
        return MLFQ.selectNext(from: try pendingTasks()) { $0.isNudgeable(at: current) }
    }

    public func task(withID id: UUID) throws -> TaskItem? {
        try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
    }

    /// Completes `task`; for a repeating task, also schedules and returns its next occurrence.
    /// The finished occurrence stays in Completed as history. Upcoming tasks (not available yet)
    /// can't be completed, and a series never gets a second unfinished copy.
    @discardableResult
    public func complete(_ task: TaskItem) throws -> TaskItem? {
        let completedAt = now()
        guard !task.isCompleted, task.isAvailable(at: completedAt) else { return nil }
        task.isCompleted = true
        task.completedAt = completedAt
        task.snoozedUntil = nil

        var next: TaskItem?
        if let nextDate = task.repeatRule.nextOccurrence(after: completedAt) {
            let series = task.seriesID ?? UUID()
            task.seriesID = series
            if try unfinishedOccurrences(inSeries: series).isEmpty {
                let occurrence = TaskItem(
                    title: task.title,
                    categoryName: task.categoryName,
                    queueLevel: QueueLevel(rawValue: task.queueLevel) ?? .medium,
                    createdAt: completedAt,
                    repeatRule: task.repeatRule,
                    availableFrom: nextDate
                )
                occurrence.seriesID = series
                occurrence.notes = task.notes
                occurrence.enqueuedAt = nextDate  // joins the back of the line on the day it's due
                context.insert(occurrence)
                task.nextOccurrenceID = occurrence.id
                next = occurrence
            }
        }
        try context.save()
        return next
    }

    public func setRepeatRule(_ task: TaskItem, to rule: RepeatRule) throws {
        task.repeatRule = rule
        if rule != .never && task.seriesID == nil { task.seriesID = UUID() }
        try context.save()
    }

    /// Reopens a completed task. For a repeating task, the reopened one becomes the series' only
    /// unfinished copy: any other open or upcoming occurrence is removed. Returns what was removed
    /// so the caller can undo.
    @discardableResult
    public func reopen(_ task: TaskItem) throws -> [TaskSnapshot] {
        guard task.isCompleted else { return [] }
        var removed: [TaskSnapshot] = []
        if let series = task.seriesID {
            for other in try unfinishedOccurrences(inSeries: series) where other.id != task.id {
                removed.append(other.snapshot)
                context.delete(other)
            }
        }
        task.isCompleted = false
        task.completedAt = nil
        task.nextOccurrenceID = nil
        try context.save()
        return removed
    }

    /// Pulls an upcoming repeat into the open queues now (back of its line).
    public func makeAvailableNow(_ task: TaskItem) throws {
        guard !task.isCompleted, !task.isAvailable(at: now()) else { return }
        task.availableFrom = nil
        task.enqueuedAt = now()
        try context.save()
    }

    /// Open or upcoming (not completed) tasks in a repeating series.
    public func unfinishedOccurrences(inSeries series: UUID) throws -> [TaskItem] {
        let target: UUID? = series
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.seriesID == target && $0.isCompleted == false }
        )
        return try context.fetch(descriptor)
    }

    /// One-time repair for data from before series existed: gives legacy repeating tasks a `seriesID`
    /// (grouping copies by title + category + repeat rule) and removes duplicate unfinished copies,
    /// keeping the one that's already open (else the soonest upcoming). Returns how many were removed.
    @discardableResult
    public func repairRepeatingSeries() throws -> Int {
        let all = try allTasks()
        var legacyGroups: [String: UUID] = [:]
        for task in all where task.seriesID == nil && task.repeatRule != .never {
            let key = "\(task.title)\u{1F}\(task.categoryName)\u{1F}\(task.repeatRule.rawValue)"
            let series = legacyGroups[key] ?? UUID()
            legacyGroups[key] = series
            task.seriesID = series
        }

        let now = now()
        var removed = 0
        let unfinished = all.filter { !$0.isCompleted && $0.seriesID != nil }
        for (_, copies) in Dictionary(grouping: unfinished, by: { $0.seriesID! }) where copies.count > 1 {
            let keep = copies.filter { $0.isAvailable(at: now) }.min(by: MLFQ.isOrderedBefore)
                ?? copies.min { ($0.availableFrom ?? .distantPast) < ($1.availableFrom ?? .distantPast) }
            for copy in copies where copy.id != keep?.id {
                context.delete(copy)
                removed += 1
            }
        }
        if context.hasChanges { try context.save() }
        return removed
    }

    public func delete(_ task: TaskItem) throws {
        context.delete(task)
        try context.save()
    }

    /// Removes every completed task; returns their snapshots so the caller can offer undo.
    @discardableResult
    public func deleteCompleted() throws -> [TaskSnapshot] {
        let done = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isCompleted == true }))
        let snapshots = done.map(\.snapshot)
        for task in done { context.delete(task) }
        try context.save()
        return snapshots
    }

    /// Re-creates a task from a snapshot (undoing a delete).
    @discardableResult
    public func insert(_ snapshot: TaskSnapshot) throws -> TaskItem {
        let task = TaskItem(snapshot: snapshot)
        context.insert(task)
        try context.save()
        return task
    }

    /// Rolls an existing task back to a snapshot (undoing an edit).
    public func restore(_ task: TaskItem, to snapshot: TaskSnapshot) throws {
        task.restore(snapshot)
        try context.save()
    }

    public func setTitle(_ task: TaskItem, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        task.title = trimmed
        try context.save()
    }

    public func setNotes(_ task: TaskItem, to notes: String) throws {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.notes = trimmed.isEmpty ? nil : notes
        try context.save()
    }

    public func setDueDate(_ task: TaskItem, to date: Date?) throws {
        task.dueDate = date
        try context.save()
    }

    /// Manual reordering: puts `task` directly in front of `target` in target's queue (moving queues if needed).
    public func move(_ task: TaskItem, before target: TaskItem) throws {
        guard task.id != target.id else { return }
        let line = try pendingTasks().filter { $0.queueLevel == target.queueLevel && $0.id != task.id }
        guard let index = line.firstIndex(where: { $0.id == target.id }) else { return }
        let after = target.queuePosition.timeIntervalSinceReferenceDate
        let before = index > 0 ? line[index - 1].queuePosition.timeIntervalSinceReferenceDate : after - 60
        if task.queueLevel != target.queueLevel {
            task.queueLevel = target.queueLevel
            task.skipCount = 0
        }
        task.enqueuedAt = Date(timeIntervalSinceReferenceDate: (before + after) / 2)
        try context.save()
    }

    /// A manual move joins the back of the new queue and restarts aging there.
    public func setQueueLevel(_ task: TaskItem, to level: QueueLevel) throws {
        task.queueLevel = level.rawValue
        task.skipCount = 0
        task.enqueuedAt = now()
        try context.save()
    }

    public func setCategory(_ task: TaskItem, to categoryName: String) throws {
        task.categoryName = categoryName
        try context.save()
    }

    public func skip(_ task: TaskItem) throws {
        MLFQ.recordSkip(task, direction: skipDirection(for: task.categoryName), threshold: skipThreshold, at: now())
        try context.save()
    }

    public func snooze(_ task: TaskItem, for interval: TimeInterval = 3600) throws {
        task.snoozedUntil = now().addingTimeInterval(interval)
        try context.save()
    }

    public func unsnooze(_ task: TaskItem) throws {
        task.snoozedUntil = nil
        try context.save()
    }
}
