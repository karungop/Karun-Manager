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

    private var dismissWork: DispatchWorkItem?

    func show(_ toast: Toast, onAction: @escaping (NotificationManager.Action?) -> Void) {
        let finish = { [weak self] (action: NotificationManager.Action?) in
            self?.dismiss()
            onAction(action)
        }
        let hosting = NSHostingView(
            rootView: ToastView(toast: toast, onAction: finish, onClose: { [weak self] in self?.dismiss() })
        )
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

        dismissWork?.cancel()
        guard !toast.hasTaskActions else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.informationalLifetime, execute: work)
    }

    func dismiss() {
        dismissWork?.cancel()
        panel.orderOut(nil)
        panel.contentView = nil
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
