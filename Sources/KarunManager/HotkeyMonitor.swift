import AppKit

/// Option+Space toggle. The global monitor sees keys aimed at other apps; the local one covers
/// the case where one of our own panels is key (global monitors skip our own events).
@MainActor
final class HotkeyMonitor {
    private nonisolated static let spaceKeyCode: UInt16 = 49
    private var monitors: [Any] = []

    init(handler: @escaping @MainActor () -> Void) {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            guard Self.isHotkey(event) else { return }
            MainActor.assumeIsolated { handler() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            guard Self.isHotkey(event) else { return event }
            MainActor.assumeIsolated { handler() }
            return nil
        }) {
            monitors.append(local)
        }
    }

    private nonisolated static func isHotkey(_ event: NSEvent) -> Bool {
        event.keyCode == spaceKeyCode
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
    }
}
