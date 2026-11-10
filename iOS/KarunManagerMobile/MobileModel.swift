import CoreData
import Foundation
import KarunManagerCore
import Observation
import SwiftData

/// The iPhone app's state: open tasks in queue order, plus the three things you can do here (add,
/// complete, delete). Everything else (categories, skip rules, nudges, repeats, due dates) is managed on
/// the Mac and arrives through iCloud.
@MainActor @Observable
final class MobileModel {
    enum SyncStatus: Equatable {
        /// Tasks sync with the Mac through iCloud.
        case on
        /// Built for iCloud, but no account is signed in on this device; tasks sync once one is.
        case noAccount
        /// Built without iCloud (no Local.xcconfig); tasks stay on this device.
        case off
        /// `--demo` / `--in-memory`: a throwaway list.
        case demo
    }

    struct UndoAction: Identifiable {
        let id = UUID()
        let message: String
        let perform: @MainActor (TaskStore) throws -> Void
    }

    let store: TaskStore
    let syncStatus: SyncStatus
    /// Open tasks that are available now (scheduled repeats stay hidden until their day), in queue order.
    private(set) var tasks: [TaskItem] = []
    private(set) var categories: [String] = TaskCategory.defaults
    /// Shown above the list when the store couldn't be opened or saved.
    private(set) var problem: String?
    /// The most recent completion or deletion, offered for a few seconds as "Undo".
    private(set) var undo: UndoAction?

    @ObservationIgnored private var preferences: SyncedPreferences?
    @ObservationIgnored private var remoteObserver: NSObjectProtocol?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var undoExpiry: Task<Void, Never>?

    init(options: LaunchOptions = LaunchOptions(arguments: CommandLine.arguments)) {
        let cloudContainer = options.inMemory ? nil : Self.configuredCloudKitContainer
        syncStatus = if options.inMemory { .demo }
            else if cloudContainer == nil { .off }
            else if FileManager.default.ubiquityIdentityToken == nil { .noAccount }
            else { .on }

        let (container, openProblem) = Self.openContainer(inMemory: options.inMemory, cloudKitContainer: cloudContainer)
        problem = openProblem
        store = TaskStore(container: container, defaults: Self.makeDefaults(inMemory: options.inMemory))
        if options.demo { try? store.seedDemoData() }
        _ = try? store.repairRepeatingSeries()
        reload()
        startSync()
    }

    // MARK: Reading

    func tasks(in level: QueueLevel) -> [TaskItem] {
        tasks.filter { $0.queueLevel == level.rawValue }
    }

    /// The task a nudge would show on the Mac right now.
    var upNextID: UUID? {
        let now = Date()
        return MLFQ.selectNext(from: tasks) { $0.isNudgeable(at: now) }?.id
    }

    /// Re-reads tasks and categories. Also called when the app returns to the foreground, so a repeat
    /// whose day has come appears.
    func reload() {
        categories = store.categories
        let now = Date()
        tasks = ((try? store.pendingTasks()) ?? []).filter { $0.isAvailable(at: now) }
    }

    // MARK: Changing

    /// Adds a task. A prefix like "buy:" or "work:" picks the category, as on the Mac. Returns false for blank text.
    @discardableResult
    func add(_ text: String, category: String, queue: QueueLevel) -> Bool {
        guard let parsed = CaptureParser.parse(text, categories: categories) else { return false }
        let categoryName = parsed.hadPrefix || !categories.contains(category) ? parsed.categoryName : category
        perform { try $0.add(title: parsed.title, categoryName: categoryName, queueLevel: queue) }
        return true
    }

    /// Completes a task (a repeating one schedules its next occurrence, as on the Mac).
    func complete(_ task: TaskItem) {
        guard !task.isCompleted, task.isAvailable(at: Date()) else { return }
        let before = task.snapshot
        perform { try $0.complete(task) }
        let spawned = task.nextOccurrenceID
        offerUndo("Completed “\(before.title)”") { store in
            if let spawned, let next = try store.task(withID: spawned), !next.isCompleted { try store.delete(next) }
            if let task = try store.task(withID: before.id) { try store.restore(task, to: before) }
        }
    }

    func delete(_ task: TaskItem) {
        let snapshot = task.snapshot
        perform { try $0.delete(task) }
        offerUndo("Deleted “\(snapshot.title)”") { try $0.insert(snapshot) }
    }

    func performUndo() {
        guard let action = undo else { return }
        dismissUndo()
        perform(action.perform)
    }

    func dismissUndo() {
        undo = nil
        undoExpiry?.cancel()
    }

    private func perform(_ change: (TaskStore) throws -> Void) {
        do {
            try change(store)
        } catch {
            problem = "Couldn't save that change: \(error.localizedDescription)"
        }
        reload()
    }

    private func offerUndo(_ message: String, _ perform: @escaping @MainActor (TaskStore) throws -> Void) {
        let action = UndoAction(message: message, perform: perform)
        undo = action
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, self?.undo?.id == action.id else { return }
            self?.undo = nil
        }
    }

    // MARK: Sync

    /// The iCloud container named in Info.plist (set from Local.xcconfig), or nil for a local-only build.
    /// A build-time value rather than a runtime entitlement check: iOS has no public API to read entitlements,
    /// and asking SwiftData for a container the app isn't entitled to would crash.
    private static var configuredCloudKitContainer: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "KMCloudKitContainer") as? String
        return value?.isEmpty == false ? value : nil
    }

    /// Tasks: SwiftData's CloudKit mirroring, then the same duplicate repair the Mac runs. Preferences:
    /// only categories matter here, and they arrive through the shared key-value store.
    private func startSync() {
        guard syncStatus == .on || syncStatus == .noAccount else { return }
        refreshAfterRemoteChange()
        remoteObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRemoteRefresh() }
        }
        let preferences = SyncedPreferences(defaults: .standard, domain: Bundle.main.bundleIdentifier ?? "")
        preferences.onRemoteChange = { [weak self] in self?.reload() }
        preferences.start()
        self.preferences = preferences
        reload()
    }

    /// iCloud imports arrive in bursts; refresh once they settle.
    private func scheduleRemoteRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.refreshAfterRemoteChange()
        }
    }

    private func refreshAfterRemoteChange() {
        _ = try? store.repairSyncConflicts()
        reload()
    }

    // MARK: Setup

    /// Opens the task database. Unlike the Mac there's no alert to ask first: a store that can't be opened is
    /// renamed (never deleted) and a fresh one started; with iCloud on, tasks download again.
    private static func openContainer(inMemory: Bool, cloudKitContainer: String?) -> (ModelContainer, String?) {
        do {
            return (try TaskStore.makeContainer(inMemory: inMemory, cloudKitContainer: cloudKitContainer), nil)
        } catch {
            TaskStore.moveStoreAside()
            if let fresh = try? TaskStore.makeContainer(cloudKitContainer: cloudKitContainer) {
                return (fresh, "Your task database couldn't be opened, so it was set aside and a new one started.")
            }
            // Last resort: keep the app usable for this session.
            let memory = try! TaskStore.makeContainer(inMemory: true)
            return (memory, "Tasks can't be saved on this iPhone right now: \(error.localizedDescription)")
        }
    }

    private static func makeDefaults(inMemory: Bool) -> UserDefaults {
        guard inMemory else { return .standard }
        let suite = "com.karungopal.KarunManager.ephemeral"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite) ?? .standard
    }
}
