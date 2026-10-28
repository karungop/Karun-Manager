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

    public init(
        id: UUID = UUID(),
        title: String,
        categoryName: String = TaskCategory.thingsToDo,
        queueLevel: QueueLevel = .medium,
        skipCount: Int = 0,
        createdAt: Date = Date(),
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.categoryName = categoryName
        self.queueLevel = queueLevel.rawValue
        self.skipCount = skipCount
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }
}
