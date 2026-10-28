import Foundation
import SwiftData
import Testing
@testable import KarunManagerCore

@MainActor
struct MLFQTests {
    private func makeStore(now: @escaping () -> Date = { Date() }) throws -> TaskStore {
        TaskStore(container: try TaskStore.makeContainer(inMemory: true), now: now)
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
        let task = try store.add(title: "File taxes")
        #expect(task.queueLevel == QueueLevel.medium.rawValue)

        for _ in 0..<4 { try store.skip(task) }
        #expect(task.queueLevel == QueueLevel.medium.rawValue)
        #expect(task.skipCount == 4)

        try store.skip(task)

        let refetched = try #require(try store.pendingTasks().first)
        #expect(refetched.queueLevel == QueueLevel.high.rawValue)
        #expect(refetched.skipCount == 0)
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
}
