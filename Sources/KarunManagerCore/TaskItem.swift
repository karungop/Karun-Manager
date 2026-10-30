import Foundation
import SwiftData

public enum QueueLevel: Int, CaseIterable, Sendable {
    case high = 0
    case medium = 1
    case low = 2
}

public enum TaskCategory {
    public static let thingsToDo = "Things to do"
    public static let thingsToBuy = "Things to buy"
    public static let peopleToCall = "People to call"

    /// The starting set; users can add, rename and delete categories (see `TaskStore.categories`).
    public static let defaults = [thingsToDo, thingsToBuy, peopleToCall]
}

@Model
public final class TaskItem {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var categoryName: String
    public var queueLevel: Int
    public var skipCount: Int
    public var createdAt: Date
    public var isCompleted: Bool
    public var completedAt: Date?
    /// `RepeatRule` raw value; nil means it doesn't repeat. Optional so existing stores migrate automatically.
    public var repeatRuleRaw: String?
    /// A scheduled repeat stays hidden from nudges (and listed under "Upcoming") until this moment.
    public var availableFrom: Date?
    /// When the task joined the back of its current queue. Skips and moves reset it, which is what
    /// makes each level round-robin. Optional so existing stores migrate; falls back to `createdAt`.
    public var enqueuedAt: Date?
    /// Free-form details shown in the inspector.
    public var notes: String?
    /// Optional deadline; purely informational (shown on the row, red once overdue).
    public var dueDate: Date?
    /// Hidden from nudges until this moment. Persisted so snoozes survive a relaunch.
    public var snoozedUntil: Date?
    /// For a completed repeating task: the occurrence its completion scheduled (used to undo a completion).
    public var nextOccurrenceID: UUID?
    /// Hidden identity shared by every occurrence of one repeating task. The store keeps at most one
    /// unfinished (open or upcoming) task per series. `id` stays unique per task.
    public var seriesID: UUID?

    public func isSnoozed(at date: Date) -> Bool {
        (snoozedUntil ?? .distantPast) > date
    }

    /// Open, available (not a future repeat) and not snoozed: something a nudge may show.
    public func isNudgeable(at date: Date) -> Bool {
        !isCompleted && isAvailable(at: date) && !isSnoozed(at: date)
    }

    /// The task's place in line within its queue: earlier is closer to the front.
    public var queuePosition: Date {
        enqueuedAt ?? createdAt
    }

    public var repeatRule: RepeatRule {
        get { repeatRuleRaw.flatMap(RepeatRule.init(rawValue:)) ?? .never }
        set { repeatRuleRaw = newValue == .never ? nil : newValue.rawValue }
    }

    public func isAvailable(at date: Date) -> Bool {
        (availableFrom ?? .distantPast) <= date
    }

    public init(
        id: UUID = UUID(),
        title: String,
        categoryName: String = TaskCategory.thingsToDo,
        queueLevel: QueueLevel = .medium,
        skipCount: Int = 0,
        createdAt: Date = Date(),
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        repeatRule: RepeatRule = .never,
        availableFrom: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.categoryName = categoryName
        self.queueLevel = queueLevel.rawValue
        self.skipCount = skipCount
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.repeatRuleRaw = repeatRule == .never ? nil : repeatRule.rawValue
        self.availableFrom = availableFrom
        self.seriesID = repeatRule == .never ? nil : UUID()
    }
}

/// A value copy of every stored field, used for undo (re-inserting a deleted task or rolling back an edit).
public struct TaskSnapshot: Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let categoryName: String
    public let queueLevel: Int
    public let skipCount: Int
    public let createdAt: Date
    public let isCompleted: Bool
    public let completedAt: Date?
    public let repeatRuleRaw: String?
    public let availableFrom: Date?
    public let enqueuedAt: Date?
    public let notes: String?
    public let dueDate: Date?
    public let snoozedUntil: Date?
    public let nextOccurrenceID: UUID?
    public let seriesID: UUID?
}

extension TaskItem {
    public var snapshot: TaskSnapshot {
        TaskSnapshot(
            id: id, title: title, categoryName: categoryName, queueLevel: queueLevel, skipCount: skipCount,
            createdAt: createdAt, isCompleted: isCompleted, completedAt: completedAt, repeatRuleRaw: repeatRuleRaw,
            availableFrom: availableFrom, enqueuedAt: enqueuedAt, notes: notes, dueDate: dueDate,
            snoozedUntil: snoozedUntil, nextOccurrenceID: nextOccurrenceID, seriesID: seriesID
        )
    }

    /// Overwrites every field except `id` with the snapshot's values.
    public func restore(_ snapshot: TaskSnapshot) {
        title = snapshot.title
        categoryName = snapshot.categoryName
        queueLevel = snapshot.queueLevel
        skipCount = snapshot.skipCount
        createdAt = snapshot.createdAt
        isCompleted = snapshot.isCompleted
        completedAt = snapshot.completedAt
        repeatRuleRaw = snapshot.repeatRuleRaw
        availableFrom = snapshot.availableFrom
        enqueuedAt = snapshot.enqueuedAt
        notes = snapshot.notes
        dueDate = snapshot.dueDate
        snoozedUntil = snapshot.snoozedUntil
        nextOccurrenceID = snapshot.nextOccurrenceID
        seriesID = snapshot.seriesID
    }

    public convenience init(snapshot: TaskSnapshot) {
        self.init(id: snapshot.id, title: snapshot.title)
        restore(snapshot)
    }
}
