import Foundation
import KarunManagerCore
import Observation

enum SidebarItem: Hashable {
    case allOpen
    case queue(QueueLevel)
    case category(String)
    /// Repeats waiting for their next day; they move to the open pages on their own.
    case upcoming
    case completed

    var title: String {
        switch self {
        case .allOpen: "All open"
        case .queue(let level): level.title
        case .category(let name): name
        case .upcoming: "Upcoming"
        case .completed: "Completed"
        }
    }

    var symbol: String {
        switch self {
        case .allOpen: "tray.full"
        case .queue: "square.stack.3d.up"
        case .category(let name): CategoryStyle.symbol(name)
        case .upcoming: "calendar"
        case .completed: "checkmark.circle"
        }
    }

    /// Open pages show only tasks available now; future repeats live on Upcoming until their day.
    func includes(_ task: TaskItem, now: Date) -> Bool {
        let isOpen = !task.isCompleted && task.isAvailable(at: now)
        switch self {
        case .allOpen: return isOpen
        case .queue(let level): return isOpen && task.queueLevel == level.rawValue
        case .category(let name): return isOpen && task.categoryName == name
        case .upcoming: return !task.isCompleted && !task.isAvailable(at: now)
        case .completed: return task.isCompleted
        }
    }

    /// Pages where new tasks can be added (and the composer shows).
    var acceptsNewTasks: Bool {
        switch self {
        case .allOpen, .queue, .category: true
        case .upcoming, .completed: false
        }
    }
}

/// Everything the window derives from the task list, computed once per render instead of per view.
struct LibraryIndex {
    let now: Date
    /// 1-based place in line within each queue (available open tasks only).
    let positions: [UUID: Int]
    let upNext: TaskItem?
    /// Open, available tasks per sidebar item; future repeats ("Upcoming") aren't counted.
    let counts: [SidebarItem: Int]

    init(tasks: [TaskItem], now: Date, categories: [String]) {
        self.now = now
        let line = tasks.filter { !$0.isCompleted && $0.isAvailable(at: now) }.sorted(by: MLFQ.isOrderedBefore)
        var positions: [UUID: Int] = [:]
        var perQueue: [Int: Int] = [:]
        for task in line {
            perQueue[task.queueLevel, default: 0] += 1
            positions[task.id] = perQueue[task.queueLevel]
        }
        self.positions = positions
        upNext = line.first { !$0.isSnoozed(at: now) }

        var counts: [SidebarItem: Int] = [
            .allOpen: line.count,
            .upcoming: tasks.filter { !$0.isCompleted && !$0.isAvailable(at: now) }.count,
            .completed: tasks.filter(\.isCompleted).count,
        ]
        for level in QueueLevel.allCases { counts[.queue(level)] = perQueue[level.rawValue] ?? 0 }
        for name in categories { counts[.category(name)] = line.filter { $0.categoryName == name }.count }
        self.counts = counts
    }
}

/// Shown after an undoable change ("Deleted “X” · Undo").
struct UndoBanner: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

/// UI state for the main window. Data itself comes from SwiftData `@Query`; mutations go through `TaskStore`.
@MainActor
@Observable
final class LibraryModel {
    let store: TaskStore
    let settings: AppSettings
    var selection: SidebarItem = .allOpen {
        didSet { applyComposerDefaults() }
    }
    var selectedTaskID: UUID?
    var lastNudgeAt: Date?
    /// Advanced by the app's 30s tick so "Upcoming" repeats and snoozes surface without a relaunch.
    var now = Date()
    /// False when macOS refused notification permission and in-app banners stand in.
    var usesSystemNotifications = true
    /// Filters the current page by title and notes.
    var searchText = ""

    // Composer state lives here so window shortcuts can target it (⌘1–3 while typing a new task).
    var composerCategory = TaskCategory.thingsToDo
    var composerLevel = QueueLevel.medium
    var composerRepeat = RepeatRule.never
    var isComposerFocused = false

    /// Bumped to ask a view to take focus.
    private(set) var composerFocusRequest = 0
    private(set) var searchFocusRequest = 0
    private(set) var titleEditRequest = 0
    /// Bumped after every mutation, for state SwiftData can't observe (categories, skip settings).
    private(set) var revision = 0

    /// Every task, in queue order. Reloaded after each change rather than using SwiftData's `@Query`,
    /// which doesn't notice a task re-inserted with a previously deleted ID (undoing a delete).
    private(set) var tasks: [TaskItem] = []

    @ObservationIgnored let undoManager = UndoManager()
    var undoBanner: UndoBanner?

    @ObservationIgnored var onOpenSettings: () -> Void = {}
    /// After any change: lets the app reschedule due reminders.
    @ObservationIgnored var didMutate: () -> Void = {}
    /// A skip crossed the threshold and moved the task (old level, new level).
    @ObservationIgnored var onSkipMovedTask: (TaskItem, QueueLevel, QueueLevel) -> Void = { _, _, _ in }

    init(store: TaskStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        composerCategory = store.categories.first ?? TaskCategory.thingsToDo
        reloadTasks()
    }

    func reloadTasks() {
        do {
            tasks = try store.allTasks()
        } catch {
            NSLog("KarunManager: failed to load tasks: \(error)")
        }
    }

    // MARK: Store-backed settings (read `revision` so views refresh when they change)

    var categories: [String] {
        _ = revision
        return store.categories
    }

    var skipThreshold: Int {
        _ = revision
        return store.skipThreshold
    }

    func setSkipThreshold(_ value: Int) {
        perform { $0.setSkipThreshold(value) }
    }

    func skipDirection(for categoryName: String) -> SkipDirection {
        _ = revision
        return store.skipDirection(for: categoryName)
    }

    func setSkipDirection(_ direction: SkipDirection, for categoryName: String) {
        perform { $0.setSkipDirection(direction, for: categoryName) }
    }

    // MARK: Focus requests

    func focusComposer() {
        if !selection.acceptsNewTasks { selection = .allOpen }
        composerFocusRequest += 1
    }

    func focusSearch() {
        searchFocusRequest += 1
    }

    func editSelectedTitle() {
        guard selectedTaskID != nil else { return }
        titleEditRequest += 1
    }

    // MARK: Adding

    /// A `buy:` / `call:` / `<category>:` prefix in the text wins over the chosen category.
    @discardableResult
    func addTask(text: String, categoryName: String, level: QueueLevel, repeatRule: RepeatRule = .never) -> Bool {
        guard let parsed = CaptureParser.parse(text, categories: store.categories) else { return false }
        let category = parsed.hadPrefix ? parsed.categoryName : categoryName
        perform { try $0.add(title: parsed.title, categoryName: category, queueLevel: level, repeatRule: repeatRule) }
        return true
    }

    @discardableResult
    func submitComposer(_ text: String) -> Bool {
        guard addTask(text: text, categoryName: composerCategory, level: composerLevel, repeatRule: composerRepeat) else {
            return false
        }
        composerRepeat = .never
        return true
    }

    /// New tasks inherit whichever queue or category is open in the sidebar.
    private func applyComposerDefaults() {
        switch selection {
        case .queue(let level): composerLevel = level
        case .category(let name): composerCategory = name
        default: break
        }
    }

    // MARK: Editing (undoable)

    func setQueue(_ task: TaskItem, to level: QueueLevel) {
        guard task.queueLevel != level.rawValue else { return }
        edit(task, "Moved “\(task.title)” to \(level.title)") { try $0.setQueueLevel(task, to: level) }
    }

    func setCategory(_ task: TaskItem, to categoryName: String) {
        guard task.categoryName != categoryName else { return }
        edit(task, "Moved “\(task.title)” to \(categoryName)") { try $0.setCategory(task, to: categoryName) }
    }

    func move(_ task: TaskItem, before target: TaskItem) {
        guard task.id != target.id else { return }
        edit(task, "Reordered “\(task.title)”") { try $0.move(task, before: target) }
    }

    func setRepeatRule(_ task: TaskItem, to rule: RepeatRule) {
        edit(task, "Changed repeat for “\(task.title)”") { try $0.setRepeatRule(task, to: rule) }
    }

    func setDueDate(_ task: TaskItem, to date: Date?) {
        edit(task, date == nil ? "Removed due date" : "Changed due date") { try $0.setDueDate(task, to: date) }
    }

    // Text edits aren't registered here: the text fields have their own undo while typing.
    func setTitle(_ task: TaskItem, to title: String) {
        perform { try $0.setTitle(task, to: title) }
    }

    func setNotes(_ task: TaskItem, to notes: String) {
        guard notes != (task.notes ?? "") else { return }
        perform { try $0.setNotes(task, to: notes) }
    }

    func setQueueOfSelectedTask(to level: QueueLevel) {
        guard let id = selectedTaskID, let task = try? store.task(withID: id), !task.isCompleted else { return }
        setQueue(task, to: level)
    }

    /// Every skip (HUD, notification, inspector) goes through here so queue moves get reported.
    func skip(_ task: TaskItem) {
        let before = QueueLevel(task: task)
        edit(task, "Skipped “\(task.title)”") { try $0.skip(task) }
        let after = QueueLevel(task: task)
        if after != before { onSkipMovedTask(task, before, after) }
    }

    func snooze(_ task: TaskItem) {
        edit(task, "Snoozed “\(task.title)”") { try $0.snooze(task, for: 3600) }
    }

    func unsnooze(_ task: TaskItem) {
        edit(task, "Woke “\(task.title)”") { try $0.unsnooze(task) }
    }

    func complete(_ task: TaskItem) {
        // Upcoming repeats can't be checked off until their day.
        guard !task.isCompleted, task.isAvailable(at: Date()) else { return }
        let before = task.snapshot
        perform { try $0.complete(task) }
        let spawned = task.nextOccurrenceID
        registerUndo("Completed “\(before.title)”") { model in
            model.perform { store in
                if let spawned, let next = try store.task(withID: spawned), !next.isCompleted {
                    try store.delete(next)
                }
                if let task = try store.task(withID: before.id) { try store.restore(task, to: before) }
            }
        }
    }

    func reopen(_ task: TaskItem) {
        guard task.isCompleted else { return }
        let before = task.snapshot
        var removedCopies: [TaskSnapshot] = []
        perform { removedCopies = try $0.reopen(task) }
        registerUndo("Reopened “\(before.title)”") { model in
            model.perform { store in
                if let task = try store.task(withID: before.id) { try store.restore(task, to: before) }
                for copy in removedCopies { try store.insert(copy) }
            }
        }
    }

    func makeAvailableNow(_ task: TaskItem) {
        edit(task, "Moved “\(task.title)” into the queues") { try $0.makeAvailableNow(task) }
    }

    func toggleCompleted(_ task: TaskItem) {
        task.isCompleted ? reopen(task) : complete(task)
    }

    func delete(_ task: TaskItem) {
        if selectedTaskID == task.id { selectedTaskID = nil }
        let snapshot = task.snapshot
        perform { try $0.delete(task) }
        registerUndo("Deleted “\(snapshot.title)”") { model in
            model.perform { try $0.insert(snapshot) }
        }
    }

    func clearCompleted() {
        var removed: [TaskSnapshot] = []
        perform { removed = try $0.deleteCompleted() }
        guard !removed.isEmpty else { return }
        if let id = selectedTaskID, removed.contains(where: { $0.id == id }) { selectedTaskID = nil }
        registerUndo("Cleared \(removed.count) completed") { model in
            model.perform { store in
                for snapshot in removed { try store.insert(snapshot) }
            }
        }
    }

    // MARK: Categories

    @discardableResult
    func addCategory(_ name: String) -> Bool {
        var added = false
        perform { added = $0.addCategory(name) }
        return added
    }

    @discardableResult
    func renameCategory(_ old: String, to new: String) -> Bool {
        var renamed = false
        perform { renamed = try $0.renameCategory(old, to: new) }
        guard renamed else { return false }
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        if selection == .category(old) { selection = .category(trimmed) }
        if composerCategory == old { composerCategory = trimmed }
        return true
    }

    func deleteCategory(_ name: String) {
        guard let fallback = store.categories.first(where: { $0 != name }) else { return }
        perform { try $0.deleteCategory(name, movingTasksTo: fallback) }
        if selection == .category(name) { selection = .allOpen }
        if composerCategory == name { composerCategory = fallback }
    }

    // MARK: Undo

    func undo() {
        if undoManager.canUndo { undoManager.undo() }
        undoBanner = nil
    }

    private func edit(_ task: TaskItem, _ message: String, _ change: (TaskStore) throws -> Void) {
        let before = task.snapshot
        perform(change)
        registerUndo(message) { model in
            model.perform { store in
                if let task = try store.task(withID: before.id) { try store.restore(task, to: before) }
            }
        }
    }

    private func registerUndo(_ message: String, _ handler: @escaping @MainActor (LibraryModel) -> Void) {
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { handler(model) }
        }
        undoManager.setActionName(message)
        undoBanner = UndoBanner(message: message)
    }

    // MARK: Plumbing

    /// Drag and drop carries the task's UUID string.
    func task(withDragID dragID: String, in tasks: [TaskItem]) -> TaskItem? {
        tasks.first { $0.id.uuidString == dragID }
    }

    func perform(_ action: (TaskStore) throws -> Void) {
        do {
            try action(store)
        } catch {
            NSLog("KarunManager: task update failed: \(error)")
        }
        reloadTasks()
        revision += 1
        didMutate()
    }
}
