import AppKit

enum GlobalKey: Sendable {
    /// Option+Space
    case quickCapture
    /// Esc, observed system-wide so a HUD can be dismissed after clicking away from it.
    case escape
}

/// The global monitor sees keys aimed at other apps (it can observe but never swallow them);
/// the local one covers our own windows, where a handled key is consumed.
@MainActor
final class HotkeyMonitor {
    private var monitors: [Any] = []

    /// `handler` returns whether the key was handled; only local events can actually be consumed.
    init(handler: @escaping @MainActor (_ key: GlobalKey, _ isLocal: Bool) -> Bool) {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            guard let key = Self.key(for: event) else { return }
            MainActor.assumeIsolated { _ = handler(key, false) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            guard let key = Self.key(for: event) else { return event }
            let handled = MainActor.assumeIsolated { handler(key, true) }
            return handled ? nil : event
        }) {
            monitors.append(local)
        }
    }

    private nonisolated static func key(for event: NSEvent) -> GlobalKey? {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        switch event.keyCode {
        case 49 where modifiers == .option: return .quickCapture
        case 53 where modifiers.isEmpty: return .escape
        default: return nil
        }
    }
}
