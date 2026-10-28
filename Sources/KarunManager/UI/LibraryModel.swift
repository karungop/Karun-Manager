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
    /// Advanced by the app's 30s tick so "Upcoming" repeats surface without a relaunch.
    var now = Date()
    /// Bumped to ask the composer to take focus (⌥Space / ⌘N / ribbon while the window is up).
    private(set) var composerFocusRequest = 0
    /// Bumped after every mutation, for derived state SwiftData can't observe (in-memory snoozes).
    private(set) var revision = 0

    /// After any change: lets the app reschedule due reminders.
    @ObservationIgnored var didMutate: () -> Void = {}
    /// A skip crossed the threshold and moved the task (old level, new level).
    @ObservationIgnored var onSkipMovedTask: (TaskItem, QueueLevel, QueueLevel) -> Void = { _, _, _ in }

    init(store: TaskStore) {
        self.store = store
    }

    func focusComposer() {
        if selection == .completed { selection = .allOpen }
        composerFocusRequest += 1
    }

    /// A `buy:` / `call:` / `todo:` prefix in the text wins over the composer's category chips.
    @discardableResult
    func addTask(text: String, categoryName: String, level: QueueLevel, repeatRule: RepeatRule = .never) -> Bool {
        guard let parsed = CaptureParser.parse(text) else { return false }
        let hadPrefix = parsed.title != text.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = hadPrefix ? parsed.categoryName : categoryName
        perform { try $0.add(title: parsed.title, categoryName: category, queueLevel: level, repeatRule: repeatRule) }
        return true
    }

    func setQueue(_ task: TaskItem, to level: QueueLevel) {
        guard task.queueLevel != level.rawValue else { return }
        perform { try $0.setQueueLevel(task, to: level) }
    }

    func setCategory(_ task: TaskItem, to categoryName: String) {
        guard task.categoryName != categoryName else { return }
        perform { try $0.setCategory(task, to: categoryName) }
    }

    func setRepeatRule(_ task: TaskItem, to rule: RepeatRule) {
        perform { try $0.setRepeatRule(task, to: rule) }
    }

    /// Drag and drop carries the task's UUID string.
    func task(withDragID dragID: String, in tasks: [TaskItem]) -> TaskItem? {
        tasks.first { $0.id.uuidString == dragID }
    }

    func setQueueOfSelectedTask(to level: QueueLevel) {
        guard let id = selectedTaskID,
              let task = try? store.pendingTasks().first(where: { $0.id == id }) else { return }
        setQueue(task, to: level)
    }

    /// Reads `revision` so views re-render when a direction changes (UserDefaults isn't observable).
    func skipDirection(for categoryName: String) -> SkipDirection {
        _ = revision
        return store.skipDirection(for: categoryName)
    }

    func setSkipDirection(_ direction: SkipDirection, for categoryName: String) {
        perform { $0.setSkipDirection(direction, for: categoryName) }
    }

    /// Every skip (HUD, notification, inspector) goes through here so queue moves get reported.
    func skip(_ task: TaskItem) {
        let before = QueueLevel(task: task)
        perform { try $0.skip(task) }
        let after = QueueLevel(task: task)
        if after != before { onSkipMovedTask(task, before, after) }
    }

    func complete(_ task: TaskItem) {
        perform { try $0.complete(task) }
    }

    func snooze(_ task: TaskItem) {
        perform { $0.snooze(task, for: 3600) }
    }

    func toggleCompleted(_ task: TaskItem) {
        perform { store in
            if task.isCompleted {
                try store.reopen(task)
            } else {
                try store.complete(task)
            }
        }
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
        revision += 1
        didMutate()
    }
}
