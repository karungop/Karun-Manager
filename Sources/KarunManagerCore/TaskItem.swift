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
    }
}
