import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onOpenWindow: () -> Void
    private let onQuickCapture: () -> Void
    private let onShowNextTask: () -> Void

    init(
        onOpenWindow: @escaping () -> Void,
        onQuickCapture: @escaping () -> Void,
        onShowNextTask: @escaping () -> Void
    ) {
        self.onOpenWindow = onOpenWindow
        self.onQuickCapture = onQuickCapture
        self.onShowNextTask = onShowNextTask
        super.init()
        setBadged(false)
        item.menu = makeMenu()
    }

    /// Distraction Guard's quiet signal: a filled icon means a nudge is waiting.
    func setBadged(_ badged: Bool) {
        let name = badged ? "checkmark.square.fill" : "checkmark.square"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Karun Manager")
        image?.isTemplate = true
        item.button?.image = image
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Karun Manager", action: #selector(openWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        let capture = NSMenuItem(title: "Quick Capture", action: #selector(quickCapture), keyEquivalent: " ")
        capture.keyEquivalentModifierMask = .option
        capture.target = self
        menu.addItem(capture)

        let next = NSMenuItem(title: "Show Next Task", action: #selector(showNextTask), keyEquivalent: "")
        next.target = self
        menu.addItem(next)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Karun Manager", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func openWindow() { onOpenWindow() }
    @objc private func quickCapture() { onQuickCapture() }
    @objc private func showNextTask() { onShowNextTask() }
}
