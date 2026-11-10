import AppKit
import SwiftUI

/// In-app stand-in for a system notification: a small banner in the top-right corner.
/// Used when macOS won't authorize notifications (e.g. an ad-hoc signed build).
@MainActor
final class ToastPresenter {
    struct Toast {
        let title: String
        let subtitle: String?
        let body: String
        /// Show Done / Snooze / Skip.
        let hasTaskActions: Bool
    }

    private static let width: CGFloat = 360
    /// Informational banners fade; ones with Done / Snooze / Skip stay until you act or close them,
    /// since they often arrive while you're away (they follow 2+ minutes of idle time).
    private static let informationalLifetime: TimeInterval = 12

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }()

    private struct Entry {
        let id: String
        let toast: Toast
        let onAction: (NotificationManager.Action?) -> Void
        var expiry: DispatchWorkItem?
    }

    /// Newest first. Each banner has its own lifetime, so an informational one arriving later can't
    /// push out (or time out) a banner that's still waiting for Done / Snooze / Skip.
    private var entries: [Entry] = []
    private static let maxVisible = 3

    /// `id` identifies the notification; a new banner with the same id replaces the old one.
    func show(_ toast: Toast, id: String, onAction: @escaping (NotificationManager.Action?) -> Void) {
        remove(id)
        var entry = Entry(id: id, toast: toast, onAction: onAction)
        if !toast.hasTaskActions {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.remove(id) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.informationalLifetime, execute: work)
            entry.expiry = work
        }
        entries.insert(entry, at: 0)
        // Over the limit: drop the oldest informational banner first, else the oldest of all.
        while entries.count > Self.maxVisible {
            let index = entries.lastIndex { !$0.toast.hasTaskActions } ?? entries.count - 1
            entries.remove(at: index).expiry?.cancel()
        }
        render()
    }

    func dismiss() {
        for entry in entries { entry.expiry?.cancel() }
        entries.removeAll()
        render()
    }

    private func remove(_ id: String) {
        entries.removeAll { entry in
            guard entry.id == id else { return false }
            entry.expiry?.cancel()
            return true
        }
        render()
    }

    private func render() {
        guard !entries.isEmpty else {
            panel.orderOut(nil)
            panel.contentView = nil
            return
        }
        let views = entries.map { entry in
            let id = entry.id
            return ToastView(
                toast: entry.toast,
                onAction: { [weak self] action in
                    self?.remove(id)
                    entry.onAction(action)
                },
                onClose: { [weak self] in self?.remove(id) }
            )
        }
        let hosting = NSHostingView(rootView: VStack(spacing: 8) { ForEach(views.indices, id: \.self) { views[$0] } })
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - panel.frame.width - 14,
                y: visible.maxY - panel.frame.height - 14
            ))
        }
        panel.orderFrontRegardless()
    }
}

private struct ToastView: View {
    let toast: ToastPresenter.Toast
    let onAction: (NotificationManager.Action?) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.square.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textNormal)
                    if let subtitle = toast.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textMuted)
                    }
                    Text(toast.body)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textNormal)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                HUDCloseButton(help: "Dismiss", action: onClose)
            }
            .contentShape(Rectangle())
            .onTapGesture { onAction(nil) }

            if toast.hasTaskActions {
                HStack(spacing: 6) {
                    Button("Done") { onAction(.done) }
                        .buttonStyle(ObsidianButtonStyle(prominent: true))
                    Button("Snooze 1h") { onAction(.snooze) }
                        .buttonStyle(ObsidianButtonStyle())
                    Button("Skip") { onAction(.skip) }
                        .buttonStyle(ObsidianButtonStyle())
                }
                .padding(.leading, 28)
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.bgSecondary))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
        .environment(\.colorScheme, .dark)
    }
}
