import Foundation
import SwiftData

@MainActor
public final class TaskStore {
    /// Held strongly: a ModelContext does not keep its container alive.
    public let container: ModelContainer
    public let context: ModelContext
    private let now: () -> Date
    /// Snoozes are intentionally in-memory: the spec's data model has no snooze field.
    private var snoozedUntil: [UUID: Date] = [:]

    private let defaults: UserDefaults

    /// Per-category skip directions used until the user changes them.
    public static let defaultSkipDirections: [String: SkipDirection] = [
        TaskCategory.thingsToDo: .demote,
        TaskCategory.thingsToBuy: .promote,
        TaskCategory.peopleToCall: .promote,
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
        defaults.string(forKey: Self.skipDirectionKey(categoryName)).flatMap(SkipDirection.init(rawValue:))
            ?? Self.defaultSkipDirections[categoryName]
            ?? .promote
    }

    public func setSkipDirection(_ direction: SkipDirection, for categoryName: String) {
        defaults.set(direction.rawValue, forKey: Self.skipDirectionKey(categoryName))
    }

    private static func skipDirectionKey(_ categoryName: String) -> String {
        "skipDirection.\(categoryName)"
    }

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([TaskItem.self])
        if inMemory {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        let directory = URL.applicationSupportDirectory.appending(path: "KarunManager", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = ModelConfiguration(url: directory.appending(path: "Tasks.store"))
        return try ModelContainer(for: schema, configurations: config)
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

    /// Open tasks in queue order (the computed `queuePosition` can't go in a SortDescriptor).
    public func pendingTasks() throws -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isCompleted == false })
        return try context.fetch(descriptor).sorted(by: MLFQ.isOrderedBefore)
    }

    /// The task a nudge should show right now, skipping anything snoozed or scheduled for later.
    public func nextTask() throws -> TaskItem? {
        let current = now()
        return MLFQ.selectNext(from: try pendingTasks()) { task in
            task.isAvailable(at: current) && (snoozedUntil[task.id] ?? .distantPast) <= current
        }
    }

    /// Completes `task`; for a repeating task, also schedules and returns its next occurrence.
    /// The finished occurrence stays in Completed as history.
    @discardableResult
    public func complete(_ task: TaskItem) throws -> TaskItem? {
        let completedAt = now()
        task.isCompleted = true
        task.completedAt = completedAt
        snoozedUntil[task.id] = nil

        var next: TaskItem?
        if let nextDate = task.repeatRule.nextOccurrence(after: completedAt) {
            let occurrence = TaskItem(
                title: task.title,
                categoryName: task.categoryName,
                queueLevel: QueueLevel(rawValue: task.queueLevel) ?? .medium,
                createdAt: completedAt,
                repeatRule: task.repeatRule,
                availableFrom: nextDate
            )
            occurrence.enqueuedAt = nextDate  // joins the back of the line on the day it's due
            context.insert(occurrence)
            next = occurrence
        }
        try context.save()
        return next
    }

    public func setRepeatRule(_ task: TaskItem, to rule: RepeatRule) throws {
        task.repeatRule = rule
        try context.save()
    }

    public func reopen(_ task: TaskItem) throws {
        task.isCompleted = false
        task.completedAt = nil
        try context.save()
    }

    public func delete(_ task: TaskItem) throws {
        snoozedUntil[task.id] = nil
        context.delete(task)
        try context.save()
    }

    /// A manual re-prioritisation restarts aging at the new level.
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
        MLFQ.recordSkip(task, direction: skipDirection(for: task.categoryName), at: now())
        try context.save()
    }

    public func snooze(_ task: TaskItem, for interval: TimeInterval = 3600) {
        snoozedUntil[task.id] = now().addingTimeInterval(interval)
    }
}
