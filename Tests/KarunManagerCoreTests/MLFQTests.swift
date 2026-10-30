import Foundation
import SwiftData
import Testing
@testable import KarunManagerCore

@MainActor
struct MLFQTests {
    private func makeStore(now: @escaping () -> Date = { Date() }) throws -> TaskStore {
        // A throwaway defaults suite so skip-direction settings never leak between tests.
        let defaults = UserDefaults(suiteName: "MLFQTests.\(UUID().uuidString)")!
        return TaskStore(container: try TaskStore.makeContainer(inMemory: true), defaults: defaults, now: now)
    }

    @Test func selectsLowestQueueLevelThenOldest() throws {
        let base = Date(timeIntervalSince1970: 0)
        let oldLow = TaskItem(title: "old low", queueLevel: .low, createdAt: base)
        let newMedium = TaskItem(title: "new medium", queueLevel: .medium, createdAt: base.addingTimeInterval(200))
        let oldMedium = TaskItem(title: "old medium", queueLevel: .medium, createdAt: base.addingTimeInterval(100))
        let doneHigh = TaskItem(title: "done high", queueLevel: .high, createdAt: base, isCompleted: true)

        let next = MLFQ.selectNext(from: [oldLow, newMedium, oldMedium, doneHigh])
        #expect(next?.title == "old medium")
    }

    @Test func stayCategoryNeverChangesQueue() throws {
        let store = try makeStore()
        let task = try store.add(title: "Call the landlord", categoryName: TaskCategory.peopleToCall)
        #expect(store.skipDirection(for: task.categoryName) == .stay)

        for _ in 0..<12 { try store.skip(task) }
        let refetched = try #require(try store.pendingTasks().first)
        #expect(refetched.queueLevel == QueueLevel.medium.rawValue)
        #expect(refetched.skipCount == 12)
    }

    @Test func retiredPromoteSettingReadsAsStay() throws {
        let defaults = UserDefaults(suiteName: "MLFQTests.\(UUID().uuidString)")!
        defaults.set("promote", forKey: "skipDirection.\(TaskCategory.thingsToDo)")
        let store = TaskStore(container: try TaskStore.makeContainer(inMemory: true), defaults: defaults)
        #expect(store.skipDirection(for: TaskCategory.thingsToDo) == .stay)
    }

    @Test func demotingCategoryMovesTaskTowardSomeday() throws {
        let store = try makeStore()
        let task = try store.add(title: "Clean garage", categoryName: TaskCategory.thingsToDo)
        #expect(store.skipDirection(for: task.categoryName) == .demote)

        for _ in 0..<5 { try store.skip(task) }
        #expect(task.queueLevel == QueueLevel.low.rawValue)
        #expect(task.skipCount == 0)

        for _ in 0..<5 { try store.skip(task) }
        #expect(task.queueLevel == QueueLevel.low.rawValue)
        #expect(task.skipCount == 5)
    }

    @Test func skipDirectionIsConfigurablePerCategory() throws {
        let store = try makeStore()
        store.setSkipDirection(.stay, for: TaskCategory.thingsToDo)
        store.setSkipDirection(.demote, for: TaskCategory.peopleToCall)
        let todo = try store.add(title: "todo", categoryName: TaskCategory.thingsToDo)
        let call = try store.add(title: "call", categoryName: TaskCategory.peopleToCall)

        for _ in 0..<5 {
            try store.skip(todo)
            try store.skip(call)
        }
        #expect(todo.queueLevel == QueueLevel.medium.rawValue)
        #expect(call.queueLevel == QueueLevel.low.rawValue)
    }

    @Test func somedayTasksAreNotDemotedFurther() {
        let task = TaskItem(title: "someday", queueLevel: .low)
        for _ in 0..<7 { MLFQ.recordSkip(task, direction: .demote) }
        #expect(task.queueLevel == QueueLevel.low.rawValue)
        #expect(task.skipCount == 7)
    }

    @Test func completeSetsCompletedAtAndRemovesFromQueue() throws {
        let fixed = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore(now: { fixed })
        let task = try store.add(title: "Call Mom", categoryName: TaskCategory.peopleToCall)

        try store.complete(task)

        #expect(task.isCompleted)
        #expect(task.completedAt == fixed)
        #expect(try store.nextTask() == nil)
    }

    @Test func snoozeHidesTaskForAnHour() throws {
        var clock = Date(timeIntervalSince1970: 0)
        let store = try makeStore(now: { clock })
        let first = try store.add(title: "first")
        clock += 1
        let second = try store.add(title: "second")

        try store.snooze(first, for: 3600)
        #expect(try store.nextTask()?.id == second.id)

        clock += 3600
        #expect(try store.nextTask()?.id == first.id)
    }

    @Test func manualRequeueResetsAgingAndReopenRestoresTask() throws {
        let store = try makeStore()
        let task = try store.add(title: "Renew passport", queueLevel: .low)
        for _ in 0..<3 { try store.skip(task) }

        try store.setQueueLevel(task, to: .high)
        #expect(task.queueLevel == QueueLevel.high.rawValue)
        #expect(task.skipCount == 0)

        try store.complete(task)
        try store.reopen(task)
        #expect(!task.isCompleted && task.completedAt == nil)
        #expect(try store.nextTask()?.id == task.id)

        try store.delete(task)
        #expect(try store.pendingTasks().isEmpty)
    }

    @Test func completingRepeatingTaskSchedulesHiddenNextOccurrence() throws {
        let calendar = Calendar.current
        var clock = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 15))!
        let store = try makeStore(now: { clock })
        let task = try store.add(title: "Stretch", repeatRule: .daily)

        let next = try #require(try store.complete(task))
        #expect(task.isCompleted)
        #expect(next.repeatRule == .daily && !next.isCompleted && next.skipCount == 0)
        #expect(next.availableFrom == calendar.date(from: DateComponents(year: 2026, month: 10, day: 29)))
        #expect(try store.nextTask() == nil)

        clock = next.availableFrom!
        #expect(try store.nextTask()?.id == next.id)
    }

    @Test func nonRepeatingTaskSchedulesNothing() throws {
        let store = try makeStore()
        let task = try store.add(title: "One-off")
        #expect(try store.complete(task) == nil)
        #expect(try store.pendingTasks().isEmpty)
    }

    @Test func repeatRuleDates() {
        let calendar = Calendar.current
        func day(_ d: Int, month: Int = 10) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: 9))!
        }
        func start(_ d: Int, month: Int = 10, year: Int = 2026) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: d))!
        }
        // Oct 30 2026 is a Friday.
        #expect(RepeatRule.weekdays.nextOccurrence(after: day(30)) == start(2, month: 11))
        #expect(RepeatRule.weekly.nextOccurrence(after: day(28)) == start(4, month: 11))
        #expect(RepeatRule.biweekly.nextOccurrence(after: day(28)) == start(11, month: 11))
        #expect(RepeatRule.monthly.nextOccurrence(after: day(31)) == start(30, month: 11))
        #expect(RepeatRule.yearly.nextOccurrence(after: day(28)) == start(28, year: 2027))
        #expect(RepeatRule.never.nextOccurrence(after: day(28)) == nil)
    }

    @Test func skippingSendsTaskToBackOfItsQueue() throws {
        var clock = Date(timeIntervalSince1970: 0)
        let store = try makeStore(now: { clock })
        let titles = ["first", "second", "third"]
        for title in titles {
            try store.add(title: title, categoryName: TaskCategory.peopleToCall, queueLevel: .high)
            clock += 1
        }
        func order() throws -> [String] { try store.pendingTasks().map(\.title) }

        #expect(try store.nextTask()?.title == "first")
        try store.skip(try #require(try store.nextTask()))
        clock += 1
        #expect(try store.nextTask()?.title == "second")
        #expect(try order() == ["second", "third", "first"])

        try store.skip(try #require(try store.nextTask()))
        clock += 1
        #expect(try order() == ["third", "first", "second"])
    }

    @Test func skipThatMovesLevelLandsAtBackOfNewQueue() throws {
        var clock = Date(timeIntervalSince1970: 0)
        let store = try makeStore(now: { clock })
        let waiting = try store.add(title: "already low", categoryName: TaskCategory.thingsToDo, queueLevel: .low)
        clock += 1
        let task = try store.add(title: "demoted", categoryName: TaskCategory.thingsToDo, queueLevel: .medium)
        for _ in 0..<5 {
            clock += 1
            try store.skip(task)
        }
        #expect(task.queueLevel == QueueLevel.low.rawValue)
        #expect(try store.pendingTasks().map(\.id) == [waiting.id, task.id])
    }

    @Test func manualMoveJoinsBackOfQueue() throws {
        var clock = Date(timeIntervalSince1970: 0)
        let store = try makeStore(now: { clock })
        let old = try store.add(title: "old", queueLevel: .medium)
        clock += 1
        let urgent = try store.add(title: "urgent", queueLevel: .high)
        clock += 1
        try store.setQueueLevel(old, to: .high)
        #expect(try store.pendingTasks().map(\.id) == [urgent.id, old.id])
    }

    // MARK: Leaves-something-to-be-desired fixes

    @Test func snoozeSurvivesANewStoreOnTheSameData() throws {
        let container = try TaskStore.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "MLFQTests.\(UUID().uuidString)")!
        let clock = Date(timeIntervalSince1970: 0)
        let first = TaskStore(container: container, defaults: defaults, now: { clock })
        let task = try first.add(title: "snoozed")
        try first.snooze(task)

        let relaunched = TaskStore(container: container, defaults: defaults, now: { clock })
        #expect(try relaunched.nextTask() == nil)
        try relaunched.unsnooze(try #require(try relaunched.task(withID: task.id)))
        #expect(try relaunched.nextTask()?.id == task.id)
    }

    @Test func moveBeforePlacesTaskAheadOfTarget() throws {
        var clock = Date(timeIntervalSince1970: 0)
        let store = try makeStore(now: { clock })
        var made: [TaskItem] = []
        for title in ["a", "b", "c"] {
            made.append(try store.add(title: title, queueLevel: .high))
            clock += 10
        }
        let lowTask = try store.add(title: "low", queueLevel: .low)

        try store.move(made[2], before: made[0])
        #expect(try store.pendingTasks().map(\.title) == ["c", "a", "b", "low"])
        try store.move(made[0], before: made[1])
        #expect(try store.pendingTasks().map(\.title) == ["c", "a", "b", "low"])
        try store.move(lowTask, before: made[1])
        #expect(lowTask.queueLevel == QueueLevel.high.rawValue)
        #expect(try store.pendingTasks().map(\.title) == ["c", "a", "low", "b"])
    }

    @Test func categoriesCanBeAddedRenamedAndDeleted() throws {
        let store = try makeStore()
        #expect(store.categories == TaskCategory.defaults)
        #expect(store.addCategory("Work"))
        #expect(!store.addCategory("work"))
        #expect(!store.addCategory("  "))

        let task = try store.add(title: "ship", categoryName: "Work")
        store.setSkipDirection(.demote, for: "Work")
        #expect(try store.renameCategory("Work", to: "Job"))
        #expect(task.categoryName == "Job")
        #expect(store.skipDirection(for: "Job") == .demote)
        #expect(store.categories.last == "Job")

        #expect(try store.deleteCategory("Job", movingTasksTo: TaskCategory.thingsToDo))
        #expect(task.categoryName == TaskCategory.thingsToDo)
        #expect(!store.categories.contains("Job"))
    }

    @Test func skipThresholdIsConfigurable() throws {
        let store = try makeStore()
        store.setSkipThreshold(2)
        let task = try store.add(title: "todo", categoryName: TaskCategory.thingsToDo)
        try store.skip(task)
        try store.skip(task)
        #expect(task.queueLevel == QueueLevel.low.rawValue)
        store.setSkipThreshold(100)
        #expect(store.skipThreshold == 20)
    }

    @Test func snapshotsUndoDeletesAndEdits() throws {
        let store = try makeStore()
        let task = try store.add(title: "Original", categoryName: TaskCategory.thingsToBuy, queueLevel: .low)
        try store.setNotes(task, to: "some notes")
        let before = task.snapshot

        try store.setTitle(task, to: "Renamed")
        try store.setQueueLevel(task, to: .high)
        try store.restore(task, to: before)
        #expect(task.snapshot == before)

        try store.delete(task)
        #expect(try store.pendingTasks().isEmpty)
        let back = try store.insert(before)
        #expect(back.snapshot == before)
    }

    @Test func clearingCompletedOnlyRemovesDoneTasks() throws {
        let store = try makeStore()
        let open = try store.add(title: "open")
        let done = try store.add(title: "done")
        try store.complete(done)
        let removed = try store.deleteCompleted()
        #expect(removed.map(\.title) == ["done"])
        #expect(try store.pendingTasks().map(\.id) == [open.id])
    }

    // MARK: Really-bad fixes

    @Test func reopeningARepeatingTaskRemovesItsScheduledCopy() throws {
        let store = try makeStore()
        let task = try store.add(title: "Water plants", repeatRule: .weekly)
        let next = try #require(try store.complete(task))
        #expect(next.seriesID == task.seriesID)

        let removed = try store.reopen(task)
        #expect(removed.map(\.id) == [next.id])
        #expect(try store.pendingTasks().map(\.id) == [task.id])
    }

    /// The reported bug: complete → reopen → complete, repeated, piled up copies in Upcoming.
    @Test func completeReopenCyclesNeverDuplicateTheSeries() throws {
        let store = try makeStore()
        let task = try store.add(title: "Water plants", repeatRule: .weekly)
        for _ in 0..<5 {
            try store.complete(task)
            try store.reopen(task)
        }
        try store.complete(task)
        let series = try #require(task.seriesID)
        #expect(try store.unfinishedOccurrences(inSeries: series).count == 1)
    }

    @Test func upcomingTasksCannotBeCompleted() throws {
        let store = try makeStore()
        let task = try store.add(title: "Water plants", repeatRule: .weekly)
        let upcoming = try #require(try store.complete(task))
        #expect(try store.complete(upcoming) == nil)
        #expect(!upcoming.isCompleted)
        #expect(try store.unfinishedOccurrences(inSeries: upcoming.seriesID!).map(\.id) == [upcoming.id])
    }

    @Test func makeAvailableNowPullsTheRepeatIntoTheQueues() throws {
        let store = try makeStore()
        let task = try store.add(title: "Water plants", repeatRule: .weekly)
        let upcoming = try #require(try store.complete(task))
        #expect(try store.nextTask() == nil)
        try store.makeAvailableNow(upcoming)
        #expect(try store.nextTask()?.id == upcoming.id)
    }

    @Test func completingWhileACopyIsAlreadyUnfinishedSchedulesNothing() throws {
        let store = try makeStore()
        let task = try store.add(title: "Stretch", repeatRule: .daily)
        let next = try #require(try store.complete(task))
        try store.makeAvailableNow(next)
        try store.complete(next)  // schedules the copy after next
        let reopened = try store.reopen(task)
        #expect(reopened.count == 1)  // that copy goes; task is the series' one open task again
        let series = try #require(task.seriesID)
        #expect(try store.unfinishedOccurrences(inSeries: series).map(\.id) == [task.id])
    }

    @Test func repairMergesLegacyDuplicates() throws {
        let store = try makeStore()
        // Legacy data: three unlinked weekly copies (no seriesID), one open and two upcoming.
        for offset in [nil, 86_400.0, 2 * 86_400.0] as [Double?] {
            let copy = TaskItem(title: "Water plants", repeatRule: .weekly,
                                availableFrom: offset.map { Date().addingTimeInterval($0) })
            copy.seriesID = nil
            store.context.insert(copy)
        }
        try store.context.save()

        #expect(try store.repairRepeatingSeries() == 2)
        let left = try store.pendingTasks()
        #expect(left.count == 1)
        #expect(left.first?.availableFrom == nil)  // kept the open one
        #expect(try store.repairRepeatingSeries() == 0)  // idempotent
    }
}
