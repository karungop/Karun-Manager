import Foundation
import KarunManagerCore
import Observation

enum SidebarItem: Hashable {
    case allOpen
    case queue(QueueLevel)
    case category(String)
    case completed

    var title: String {
        switch self {
        case .allOpen: "All open"
        case .queue(let level): level.title
        case .category(let name): name
        case .completed: "Completed"
        }
    }

    var symbol: String {
        switch self {
        case .allOpen: "tray.full"
        case .queue: "square.stack.3d.up"
        case .category(let name): CategoryStyle.symbol(name)
        case .completed: "checkmark.circle"
        }
    }

    func includes(_ task: TaskItem) -> Bool {
        switch self {
        case .allOpen: !task.isCompleted
        case .queue(let level): !task.isCompleted && task.queueLevel == level.rawValue
        case .category(let name): !task.isCompleted && task.categoryName == name
        case .completed: task.isCompleted
        }
    }
}

/// UI state for the main window. Data itself comes from SwiftData `@Query`; mutations go through `TaskStore`.
@MainActor
@Observable
final class LibraryModel {
    let store: TaskStore
    var selection: SidebarItem = .allOpen
    var selectedTaskID: UUID?
    var lastNudgeAt: Date?

    @ObservationIgnored var onQuickCapture: () -> Void = {}
    @ObservationIgnored var onNudgeNow: () -> Void = {}

    init(store: TaskStore) {
        self.store = store
    }

    /// Adds a task from the inline "new task" line, inheriting the current queue or category.
    func addTask(from text: String) {
        guard let parsed = CaptureParser.parse(text) else { return }
        var categoryName = parsed.categoryName
        var level = QueueLevel.medium
        switch selection {
        case .queue(let selected): level = selected
        case .category(let selected) where categoryName == TaskCategory.thingsToDo: categoryName = selected
        default: break
        }
        perform { try $0.add(title: parsed.title, categoryName: categoryName, queueLevel: level) }
    }

    func toggleCompleted(_ task: TaskItem) {
        perform { task.isCompleted ? try $0.reopen(task) : try $0.complete(task) }
    }

    func delete(_ task: TaskItem) {
        if selectedTaskID == task.id { selectedTaskID = nil }
        perform { try $0.delete(task) }
    }

    func perform(_ action: (TaskStore) throws -> Void) {
        do {
            try action(store)
        } catch {
            NSLog("KarunManager: task update failed: \(error)")
        }
    }
}
