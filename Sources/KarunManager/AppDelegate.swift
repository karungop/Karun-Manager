import AppKit
import ApplicationServices
import KarunManagerCore
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private var store: TaskStore!
    private var monitor: SystemEventMonitoring!
    private let policy = NudgePolicy()
    private let hud = HUDPresenter()
    private var statusBar: StatusBarController!
    private var hotkey: HotkeyMonitor?
    private var idleTimer: Timer?
    private var library: LibraryModel!
    private var mainWindow: MainWindowController!
    private let notifications = NotificationManager()

    init(options: LaunchOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = TaskStore(
                container: try TaskStore.makeContainer(inMemory: options.inMemory),
                defaults: makeDefaults()
            )
            if options.demo { try store.seedDemoData() }
        } catch {
            fatalError("Failed to open task store: \(error)")
        }

        library = LibraryModel(store: store)
        mainWindow = MainWindowController(model: library)

        NotificationSetting.registerDefaults()
        notifications.requestAuthorization()
        notifications.onResponse = { [weak self] id, action in self?.handleNotification(taskID: id, action: action) }
        library.didMutate = { [weak self] in self?.syncDueReminders() }
        library.onSkipMovedTask = { [weak self] task, old, new in
            self?.notifications.postQueueChange(for: task, from: old, to: new)
        }
        syncDueReminders()

        statusBar = StatusBarController(
            onOpenWindow: { [weak self] in self?.openWindow() },
            onQuickCapture: { [weak self] in self?.quickCaptureRequested() },
            onShowNextTask: { [weak self] in self?.showNextTaskRequested() }
        )

        hotkey = HotkeyMonitor { [weak self] key, isLocal in
            self?.handleKey(key, isLocal: isLocal) ?? false
        }
        requestAccessibilityIfNeeded()

        monitor = makeMonitor()
        monitor.startObservingWake { [weak self] in self?.handle(.wake) }

        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.library.now = Date()
                self?.handle(.idleTick)
            }
        }

        if options.simulateIdle { handle(.idleTick) }
        // Launch stays quiet (menu bar only); the window opens from the menu bar or Dock icon.
        #if DEBUG
        if let directory = options.snapshotDirectory { runSnapshots(into: directory) }
        #endif
    }

    /// Clicking the Dock icon (or re-opening the app) brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWindow()
        return false
    }

    /// Switching to the app (e.g. Cmd+Tab) clears any HUD; the window is the place to act then.
    func applicationDidBecomeActive(_ notification: Notification) {
        if mainWindow.isFrontmost { hud.dismiss() }
    }

    private func openWindow() {
        hud.dismiss()
        mainWindow.show()
    }

    /// Throwaway runs (`--demo`, `--in-memory`) get a fresh preferences suite so they never touch real settings.
    private func makeDefaults() -> UserDefaults {
        guard options.inMemory else { return .standard }
        let suite = "com.karungopal.KarunManager.ephemeral"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite) ?? .standard
    }

    private func makeMonitor() -> SystemEventMonitoring {
        guard options.usesMockMonitor else { return LiveSystemEventMonitor() }
        let mock = MockSystemEventMonitor(
            systemIdleTime: options.simulateIdle ? 3600 : 0,
            frontmostBundleIdentifier: options.simulateFocus ? "com.apple.Terminal" : nil
        )
        if options.simulateWake {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated { mock.simulateWake() }
            }
        }
        return mock
    }

    /// Global key monitors only receive events once the user grants Accessibility access.
    private func requestAccessibilityIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Triggers

    private func handle(_ trigger: NudgeTrigger) {
        // Never interrupt a HUD that's already up, and never pop one over the main window.
        guard hud.current == nil, !mainWindow.isFrontmost else { return }

        let decision = policy.evaluate(
            trigger,
            now: Date(),
            lastNudgeAt: library.lastNudgeAt,
            idleTime: monitor.systemIdleTime,
            frontmostBundleID: monitor.frontmostBundleIdentifier,
            hasPendingTask: (try? store.nextTask()) != nil
        )

        switch decision {
        case .none: break
        case .showQuickCapture: showQuickCapture()
        case .showNudge: showNudge()
        case .badgeOnly: guardedNudge()
        }
    }

    /// Distraction Guard: no HUD, just the badge and (if enabled) a quiet notification.
    private func guardedNudge() {
        statusBar.setBadged(true)
        guard NotificationSetting.nudges.isEnabled, let task = try? store.nextTask() else { return }
        notifications.postNudge(for: task)
        library.lastNudgeAt = Date()  // keeps the 10-minute spacing between notifications too
    }

    // MARK: - Notifications

    private func syncDueReminders() {
        let now = Date()
        let upcoming = (try? store.pendingTasks())?.filter { !$0.isAvailable(at: now) } ?? []
        notifications.scheduleDueReminders(for: upcoming)
    }

    private func handleNotification(taskID: UUID, action: NotificationManager.Action?) {
        guard let task = try? store.pendingTasks().first(where: { $0.id == taskID }) else { return }
        statusBar.setBadged(false)
        switch action {
        case .done: library.complete(task)
        case .snooze: library.snooze(task)
        case .skip: library.skip(task)
        case nil:
            openWindow()
            library.selectedTaskID = task.id
        }
    }

    // MARK: - Keys

    private func handleKey(_ key: GlobalKey, isLocal: Bool) -> Bool {
        switch key {
        case .quickCapture:
            quickCaptureRequested()
            return true
        case .escape:
            guard hud.current != nil else { return false }
            // While the panel is key its SwiftUI views already handle Esc.
            if isLocal && hud.panel.isKeyWindow { return false }
            hud.cancel()
            return true
        }
    }

    // MARK: - Quick Capture

    /// With the window in front, capture happens in its composer; otherwise ⌥Space toggles the HUD.
    private func quickCaptureRequested() {
        if mainWindow.isFrontmost {
            library.focusComposer()
        } else if hud.current == .quickCapture {
            hud.dismiss()
        } else {
            showQuickCapture()
        }
    }

    private func showQuickCapture() {
        hud.present(.quickCapture, onCancel: { [weak self] in self?.hud.dismiss() }) {
            QuickCaptureView(
                onSubmit: { [weak self] text in self?.saveCapture(text) },
                onCancel: { [weak self] in self?.hud.dismiss() }
            )
        }
    }

    private func saveCapture(_ text: String) {
        guard addTask(fromHUD: text) else { return }
        hud.dismiss()
    }

    @discardableResult
    private func addTask(fromHUD text: String) -> Bool {
        guard let parsed = CaptureParser.parse(text) else { return false }
        library.perform { try $0.add(title: parsed.title, categoryName: parsed.categoryName) }
        return true
    }

    // MARK: - Nudge

    private func showNextTaskRequested() {
        if mainWindow.isFrontmost {
            library.selectedTaskID = try? store.nextTask()?.id
        } else {
            showNudge()
        }
    }

    private func showNudge() {
        statusBar.setBadged(false)
        guard let task = try? store.nextTask() else {
            showQuickCapture()
            return
        }
        library.lastNudgeAt = Date()
        let skip = { [weak self] in self?.resolve { $0.skip(task) } }
        hud.present(.nudge, onCancel: { skip() }) {
            NudgeView(
                task: task,
                skipDirection: store.skipDirection(for: task.categoryName),
                onDone: { [weak self] in self?.resolve { $0.complete(task) } },
                onSnooze: { [weak self] in self?.resolve { $0.snooze(task) } },
                onSkip: { skip() },
                onAdd: { [weak self] text in self?.addTask(fromHUD: text) ?? false }
            )
        }
    }

    /// HUD actions go through LibraryModel so they share reporting (queue-change notifications, reminders).
    private func resolve(_ action: (LibraryModel) -> Void) {
        action(library)
        hud.dismiss()
    }

    #if DEBUG
    /// Renders each surface offscreen-style via `cacheDisplay`, which needs no Screen Recording permission.
    private func runSnapshots(into directory: String) {
        let base = URL(filePath: directory, directoryHint: .isDirectory)
        func capture(_ view: NSView?, _ name: String) {
            guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: base.appending(path: name))
        }
        mainWindow.show()
        let steps: [(TimeInterval, () -> Void)] = [
            (1.0, { self.library.selectedTaskID = try? self.store.nextTask()?.id }),
            (1.6, { capture(self.mainWindow.window?.contentView, "main-window.png") }),
            (1.7, { self.library.selection = .queue(.medium) }),
            (2.2, { capture(self.mainWindow.window?.contentView, "queue-page.png") }),
            (2.3, { self.library.selection = .category(TaskCategory.thingsToDo) }),
            (2.8, { capture(self.mainWindow.window?.contentView, "category-page.png") }),
            (2.9, { self.showNudge() }),
            (3.4, { capture(self.hud.panel.contentView, "nudge-hud.png"); self.hud.dismiss(); self.showQuickCapture() }),
            (4.0, { capture(self.hud.panel.contentView, "quick-capture-hud.png"); NSApp.terminate(nil) }),
        ]
        for (delay, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(step) }
        }
    }
    #endif
}
