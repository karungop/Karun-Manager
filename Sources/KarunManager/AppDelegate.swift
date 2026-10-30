import AppKit
import KarunManagerCore
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private var store: TaskStore!
    private var monitor: SystemEventMonitoring!
    private let settings = AppSettings()
    private var settingsWindow: SettingsWindowController!
    private let hud = HUDPresenter()
    private var statusBar: StatusBarController!
    private var idleTimer: Timer?
    private var library: LibraryModel!
    private var mainWindow: MainWindowController!
    private let notifications = NotificationManager()

    init(options: LaunchOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = TaskStore(container: openContainer(), defaults: makeDefaults())
        if options.demo {
            do { try store.seedDemoData() } catch { NSLog("KarunManager: demo seed failed: \(error)") }
        }
        // Merge duplicate copies of repeating tasks left by older versions (keeps one per series).
        do {
            let removed = try store.repairRepeatingSeries()
            if removed > 0 { NSLog("KarunManager: removed \(removed) duplicate repeating task(s)") }
        } catch {
            NSLog("KarunManager: repeating-task repair failed: \(error)")
        }

        library = LibraryModel(store: store, settings: settings)
        mainWindow = MainWindowController(model: library)
        settingsWindow = SettingsWindowController(model: library)
        library.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        MainMenu.install(.init(
            openSettings: { [weak self] in self?.settingsWindow.show() },
            newTask: { [weak self] in
                guard let self else { return }
                if !mainWindow.isFrontmost { openWindow() }
                library.focusComposer()
            },
            find: { [weak self] in
                guard let self else { return }
                if !mainWindow.isFrontmost { openWindow() }
                library.focusSearch()
            }
        ))
        observeSettings()

        NotificationSetting.registerDefaults()
        notifications.onAvailabilityChange = { [weak self] native in
            self?.library.usesSystemNotifications = native
            self?.syncDueReminders()
        }
        notifications.requestAuthorization()
        notifications.onResponse = { [weak self] id, action in self?.handleNotification(taskID: id, action: action) }
        library.didMutate = { [weak self] in self?.syncDueReminders() }
        library.onSkipMovedTask = { [weak self] task, old, new in
            guard let self else { return }
            notifications.postQueueChange(for: task, from: old, to: new, threshold: store.skipThreshold)
        }
        syncDueReminders()

        statusBar = StatusBarController(
            onOpenWindow: { [weak self] in self?.openWindow() },
            onQuickCapture: { [weak self] in self?.quickCaptureRequested() },
            onShowNextTask: { [weak self] in self?.showNextTaskRequested() }
        )

        // Carbon hot keys: they swallow the keystroke and need no Accessibility permission.
        HotKeyCenter.shared.onPress = { [weak self] key in self?.handleHotKey(key) }
        hud.onVisibilityChange = { visible in HotKeyCenter.shared.setEscapeActive(visible) }
        applyQuickCaptureHotkey()

        monitor = makeMonitor()
        monitor.startObservingWake { [weak self] in self?.handle(.wake) }

        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.library.now = Date()
                self?.announceDueTasks()
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

    /// Opens the task database. If it can't be opened (corrupt file, failed migration), offers to set it
    /// aside and start fresh instead of crashing at launch.
    private func openContainer() -> ModelContainer {
        do {
            return try TaskStore.makeContainer(inMemory: options.inMemory)
        } catch {
            NSLog("KarunManager: failed to open task store: \(error)")
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Karun Manager couldn't open your tasks"
            alert.informativeText = "The task database couldn't be read (\(error.localizedDescription)).\n\n"
                + "“Start fresh” renames the old files with “-damaged” and the date (nothing is deleted), "
                + "then opens an empty task list."
            alert.addButton(withTitle: "Start fresh")
            alert.addButton(withTitle: "Quit")
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { exit(1) }
            TaskStore.moveStoreAside()
            do {
                return try TaskStore.makeContainer()
            } catch {
                NSLog("KarunManager: fresh store failed too, keeping tasks in memory: \(error)")
                return try! TaskStore.makeContainer(inMemory: true)
            }
        }
    }

    /// Keeps services that copy a setting in sync when it changes.
    private func observeSettings() {
        let hotkey = settings.quickCaptureHotkey
        withObservationTracking {
            notifications.dueReminderHour = settings.dueReminderHour
            _ = settings.quickCaptureHotkey
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeSettings()
                self.syncDueReminders()
                if self.settings.quickCaptureHotkey != hotkey { self.applyQuickCaptureHotkey() }
            }
        }
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

    private func applyQuickCaptureHotkey() {
        let registered = HotKeyCenter.shared.setQuickCapture(settings.quickCaptureHotkey)
        settings.quickCaptureHotkeyTaken = !registered
        statusBar.setQuickCaptureShortcut(settings.quickCaptureHotkey)
    }

    // MARK: - Triggers

    private func handle(_ trigger: NudgeTrigger) {
        // Never interrupt a HUD that's already up, and never pop one over the main window.
        guard hud.current == nil, !mainWindow.isFrontmost else {
            if options.logNudges {
                NSLog("KarunManager nudge check: skipped (hudShowing=\(hud.current != nil) windowInFront=\(mainWindow.isFrontmost))")
            }
            return
        }

        let decision = settings.nudgePolicy.evaluate(
            trigger,
            now: Date(),
            lastNudgeAt: library.lastNudgeAt,
            idleTime: monitor.systemIdleTime,
            frontmostBundleID: monitor.frontmostBundleIdentifier,
            hasPendingTask: (try? store.nextTask()) != nil
        )

        if options.logNudges {
            let since = library.lastNudgeAt.map { "\(Int(Date().timeIntervalSince($0)))s" } ?? "never"
            NSLog("KarunManager nudge check: trigger=\(trigger) idle=\(Int(monitor.systemIdleTime))s sinceLastNudge=\(since) frontmost=\(monitor.frontmostBundleIdentifier ?? "?") hasTask=\((try? store.nextTask()) != nil) decision=\(decision)")
        }
        switch decision {
        case .none: break
        // Automatic HUDs are passive: they never take the keyboard from the app you're typing in.
        case .showQuickCapture: showQuickCapture(takesFocus: false)
        case .showNudge: showNudge(takesFocus: false)
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

    private func announceDueTasks() {
        notifications.announceDueTasksIfNeeded((try? store.pendingTasks()) ?? [])
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

    private func handleHotKey(_ key: HotKeyCenter.Key) {
        switch key {
        case .quickCapture:
            quickCaptureRequested()
        case .escape:
            guard hud.current != nil else { return }
            if hud.isEngaged {
                // You're working in the HUD: Esc means what it says on the button (Skip / dismiss).
                hud.cancel()
            } else {
                // Esc from another app just puts the HUD away. It isn't counted as a skip, because
                // you may have meant it for that app.
                hud.dismiss()
            }
        }
    }

    // MARK: - Quick Capture

    /// With the window in front, capture happens in its composer. Otherwise the shortcut toggles the
    /// Quick Capture HUD, or, if a passive nudge is showing, jumps into that nudge's add-task line.
    private func quickCaptureRequested() {
        if mainWindow.isFrontmost {
            library.focusComposer()
        } else if hud.current == .nudge && !hud.isEngaged {
            hud.engage()
        } else if hud.current == .quickCapture && hud.isEngaged {
            hud.dismiss()
        } else if hud.current == .quickCapture {
            hud.engage()
        } else {
            showQuickCapture(takesFocus: true)
        }
    }

    private func showQuickCapture(takesFocus: Bool) {
        hud.present(.quickCapture, takesFocus: takesFocus, onCancel: { [weak self] in self?.hud.dismiss() }) {
            QuickCaptureView(
                focus: hud.focus,
                categories: store.categories,
                onSubmit: { [weak self] text, options in self?.saveCapture(text, options: options) },
                onCancel: { [weak self] in self?.hud.dismiss() }
            )
        }
    }

    private func saveCapture(_ text: String, options: CaptureOptions) {
        guard addTask(fromHUD: text, options: options) else { return }
        hud.dismiss()
    }

    /// A typed `buy:` / `call:` / `todo:` prefix still wins over the HUD's category menu.
    @discardableResult
    private func addTask(fromHUD text: String, options: CaptureOptions) -> Bool {
        library.addTask(text: text, categoryName: options.categoryName, level: options.level)
    }

    // MARK: - Nudge

    private func showNextTaskRequested() {
        if mainWindow.isFrontmost {
            library.selectedTaskID = try? store.nextTask()?.id
        } else {
            showNudge(takesFocus: true)
        }
    }

    private func showNudge(takesFocus: Bool) {
        statusBar.setBadged(false)
        guard let task = try? store.nextTask() else {
            showQuickCapture(takesFocus: takesFocus)
            return
        }
        library.lastNudgeAt = Date()
        let skip = { [weak self] in self?.resolve { $0.skip(task) } }
        hud.present(.nudge, takesFocus: takesFocus, onCancel: { skip() }) {
            NudgeView(
                task: task,
                focus: hud.focus,
                skipDirection: store.skipDirection(for: task.categoryName),
                skipThreshold: store.skipThreshold,
                categories: store.categories,
                onDone: { [weak self] in self?.resolve { $0.complete(task) } },
                onSnooze: { [weak self] in self?.resolve { $0.snooze(task) } },
                onSkip: { skip() },
                onAdd: { [weak self] text, options in self?.addTask(fromHUD: text, options: options) ?? false }
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
            (2.25, { self.library.selection = .upcoming }),
            (2.28, { capture(self.mainWindow.window?.contentView, "upcoming-page.png") }),
            (2.3, { self.library.selection = .category(TaskCategory.thingsToDo) }),
            (2.8, { capture(self.mainWindow.window?.contentView, "category-page.png") }),
            (2.9, { self.showNudge(takesFocus: true) }),
            (3.4, { capture(self.hud.panel.contentView, "nudge-hud.png"); self.hud.dismiss(); self.showQuickCapture(takesFocus: true) }),
            (4.0, { capture(self.hud.panel.contentView, "quick-capture-hud.png"); NSApp.terminate(nil) }),
        ]
        for (delay, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(step) }
        }
    }
    #endif
}
