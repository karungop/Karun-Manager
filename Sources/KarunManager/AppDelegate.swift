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

    init(options: LaunchOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = TaskStore(container: try TaskStore.makeContainer(inMemory: options.inMemory))
            if options.demo { try store.seedDemoData() }
        } catch {
            fatalError("Failed to open task store: \(error)")
        }

        library = LibraryModel(store: store)
        library.onQuickCapture = { [weak self] in self?.showQuickCapture() }
        library.onNudgeNow = { [weak self] in self?.showNudge() }
        mainWindow = MainWindowController(model: library)

        statusBar = StatusBarController(
            onOpenWindow: { [weak self] in self?.mainWindow.show() },
            onQuickCapture: { [weak self] in self?.showQuickCapture() },
            onShowNextTask: { [weak self] in self?.showNudge() }
        )

        hotkey = HotkeyMonitor { [weak self] in self?.toggleQuickCapture() }
        requestAccessibilityIfNeeded()

        monitor = makeMonitor()
        monitor.startObservingWake { [weak self] in self?.handle(.wake) }

        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.handle(.idleTick) }
        }

        if options.simulateIdle { handle(.idleTick) }
        // Simulation runs stay HUD-only so they can verify the no-focus-steal behaviour.
        if !options.usesMockMonitor { mainWindow.show() }
        #if DEBUG
        if let directory = options.snapshotDirectory { runSnapshots(into: directory) }
        #endif
    }

    /// Clicking the Dock icon (or re-opening the app) brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show()
        return false
    }

    private func makeMonitor() -> SystemEventMonitoring {
        guard options.usesMockMonitor else { return LiveSystemEventMonitor() }
        let mock = MockSystemEventMonitor(systemIdleTime: options.simulateIdle ? 3600 : 0)
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
        // Never interrupt something the user is already looking at.
        guard hud.current == nil else { return }

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
        case .badgeOnly: statusBar.setBadged(true)
        }
    }

    // MARK: - Quick Capture

    private func toggleQuickCapture() {
        if hud.current == .quickCapture {
            hud.dismiss()
        } else {
            showQuickCapture()
        }
    }

    private func showQuickCapture() {
        hud.present(.quickCapture) {
            QuickCaptureView(
                onSubmit: { [weak self] text in self?.saveCapture(text) },
                onCancel: { [weak self] in self?.hud.dismiss() }
            )
        }
    }

    private func saveCapture(_ text: String) {
        guard let parsed = CaptureParser.parse(text) else { return }
        do {
            try store.add(title: parsed.title, categoryName: parsed.categoryName)
        } catch {
            NSLog("KarunManager: failed to save task: \(error)")
        }
        hud.dismiss()
    }

    // MARK: - Nudge

    private func showNudge() {
        statusBar.setBadged(false)
        guard let task = try? store.nextTask() else {
            showQuickCapture()
            return
        }
        library.lastNudgeAt = Date()
        hud.present(.nudge) {
            NudgeView(
                task: task,
                onDone: { [weak self] in self?.resolve(task) { try $0.complete(task) } },
                onSnooze: { [weak self] in self?.resolve(task) { $0.snooze(task, for: 3600) } },
                onSkip: { [weak self] in self?.resolve(task) { try $0.skip(task) } }
            )
        }
    }

    private func resolve(_ task: TaskItem, _ action: (TaskStore) throws -> Void) {
        do {
            try action(store)
        } catch {
            NSLog("KarunManager: failed to update task \(task.id): \(error)")
        }
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
        let steps: [(TimeInterval, () -> Void)] = [
            (1.0, { self.library.selectedTaskID = try? self.store.nextTask()?.id }),
            (1.6, { capture(self.mainWindow.window?.contentView, "main-window.png") }),
            (1.8, { self.showNudge() }),
            (2.4, { capture(self.hud.panel.contentView, "nudge-hud.png"); self.hud.dismiss(); self.showQuickCapture() }),
            (3.0, { capture(self.hud.panel.contentView, "quick-capture-hud.png"); NSApp.terminate(nil) }),
        ]
        for (delay, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(step) }
        }
    }
    #endif
}
