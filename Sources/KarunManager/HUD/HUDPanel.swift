import AppKit
import SwiftUI

/// Spotlight-style panel: floats above other windows and takes keyboard input
/// without activating the app, so the previously active app stays frontmost.
final class HUDPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 80),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        appearance = NSAppearance(named: .darkAqua)
    }

    // Borderless windows refuse key status by default; we need it for the text field and shortcuts.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HUDPresenter {
    enum Kind { case quickCapture, nudge }

    private(set) var current: Kind?
    private var onCancel: (() -> Void)?
    private(set) lazy var panel = HUDPanel()

    /// `onCancel` is what Esc means for this HUD (dismiss for capture, skip for a nudge),
    /// so the global Esc handler can trigger it even when the panel isn't key.
    func present(_ kind: Kind, onCancel: @escaping () -> Void, @ViewBuilder content: () -> some View) {
        self.onCancel = onCancel
        // Fresh hosting view each time so SwiftUI @State (e.g. typed text) starts clean.
        let hosting = NSHostingView(rootView: content())
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        positionTopCenter()
        panel.makeKeyAndOrderFront(nil)
        current = kind
    }

    func cancel() {
        onCancel?()
    }

    func dismiss() {
        panel.orderOut(nil)
        panel.contentView = nil
        current = nil
        onCancel = nil
    }

    private func positionTopCenter() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - visible.height * 0.12
        )
        panel.setFrameOrigin(origin)
    }
}
