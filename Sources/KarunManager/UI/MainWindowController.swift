import AppKit
import SwiftUI

/// Owns the main window. The app is a Dock app while this is open and a menu-bar-only accessory otherwise.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: LibraryModel
    private(set) var window: NSWindow?

    init(model: LibraryModel) {
        self.model = model
    }

    /// The user is looking at the window: our app is active and the window is on screen.
    var isFrontmost: Bool {
        guard let window else { return false }
        return NSApp.isActive && window.isVisible && !window.isMiniaturized
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        // macOS 14 activation is cooperative and may be declined (e.g. when launched from a terminal);
        // ordering front regardless guarantees the window is at least visible.
        window.orderFrontRegardless()
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Karun Manager"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.windowBackground
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: MainWindowView(model: model).modelContainer(model.store.container)
        )
        window.center()
        window.setFrameAutosaveName("KarunManagerMainWindow")
        return window
    }
}
