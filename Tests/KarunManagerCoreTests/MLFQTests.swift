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

    @Test func fiveSkipsPromoteMediumToHighInSwiftData() throws {
        let store = try makeStore()
        let task = try store.add(title: "Call the landlord", categoryName: TaskCategory.peopleToCall)
        #expect(store.skipDirection(for: task.categoryName) == .promote)
        #expect(task.queueLevel == QueueLevel.medium.rawValue)

        for _ in 0..<4 { try store.skip(task) }
        #expect(task.queueLevel == QueueLevel.medium.rawValue)
        #expect(task.skipCount == 4)

        try store.skip(task)

        let refetched = try #require(try store.pendingTasks().first)
        #expect(refetched.queueLevel == QueueLevel.high.rawValue)
        #expect(refetched.skipCount == 0)
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
        store.setSkipDirection(.promote, for: TaskCategory.thingsToDo)
        store.setSkipDirection(.demote, for: TaskCategory.peopleToCall)
        let todo = try store.add(title: "todo", categoryName: TaskCategory.thingsToDo)
        let call = try store.add(title: "call", categoryName: TaskCategory.peopleToCall)

        for _ in 0..<5 {
            try store.skip(todo)
            try store.skip(call)
        }
        #expect(todo.queueLevel == QueueLevel.high.rawValue)
        #expect(call.queueLevel == QueueLevel.low.rawValue)
    }

    @Test func highPriorityTasksAreNotPromotedFurther() {
        let task = TaskItem(title: "urgent", queueLevel: .high)
        for _ in 0..<7 { MLFQ.recordSkip(task) }
        #expect(task.queueLevel == QueueLevel.high.rawValue)
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

        store.snooze(first, for: 3600)
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
}
