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

/// Lets the app ask a HUD's text field to take focus after it's already on screen.
@MainActor
@Observable
final class HUDFocus {
    /// Whether the HUD's text field should focus as soon as it appears.
    var focusOnAppear = false
    /// Bumped to focus the field later (e.g. pressing the Quick Capture shortcut over a passive nudge).
    private(set) var captureRequest = 0

    func requestCapture() { captureRequest += 1 }
}

@MainActor
final class HUDPresenter {
    enum Kind { case quickCapture, nudge }

    private(set) var current: Kind?
    private var onCancel: (() -> Void)?
    private(set) lazy var panel = HUDPanel()
    let focus = HUDFocus()
    /// Tells the app when a HUD appears or goes away (it registers Esc only while one is up).
    var onVisibilityChange: (Bool) -> Void = { _ in }

    /// True once the user is working in the HUD (it's the key window); false for a passive one.
    var isEngaged: Bool { current != nil && panel.isKeyWindow }

    /// - Parameters:
    ///   - takesFocus: true when the user asked for it (shortcut, menu). Automatic HUDs (wake, idle) pass
    ///     false: they float on top but leave the keyboard with whatever app you're typing in, until you
    ///     click them or press the Quick Capture shortcut.
    ///   - onCancel: what Esc means while you're working in this HUD (dismiss for capture, skip for a nudge).
    func present(
        _ kind: Kind,
        takesFocus: Bool,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: () -> some View
    ) {
        self.onCancel = onCancel
        focus.focusOnAppear = takesFocus
        // Fresh hosting view each time so SwiftUI @State (e.g. typed text) starts clean.
        let hosting = NSHostingView(rootView: content())
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        positionTopCenter()
        if takesFocus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        current = kind
        onVisibilityChange(true)
    }

    /// Makes a passive HUD active and puts the cursor in its text field.
    func engage() {
        guard current != nil else { return }
        panel.makeKeyAndOrderFront(nil)
        focus.requestCapture()
    }

    func cancel() {
        onCancel?()
    }

    func dismiss() {
        let wasVisible = current != nil
        panel.orderOut(nil)
        panel.contentView = nil
        current = nil
        onCancel = nil
        if wasVisible { onVisibilityChange(false) }
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
