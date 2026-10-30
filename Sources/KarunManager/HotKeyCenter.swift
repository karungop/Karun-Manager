import AppKit
import Carbon.HIToolbox

/// Shortcut choices for Quick Capture. (A free-form recorder is possible later; presets keep it simple.)
enum QuickCaptureHotkey: String, CaseIterable, Sendable {
    case optionSpace
    case controlOptionSpace
    case shiftOptionSpace
    case controlShiftSpace
    case off

    var title: String {
        switch self {
        case .optionSpace: "⌥ Space"
        case .controlOptionSpace: "⌃⌥ Space"
        case .shiftOptionSpace: "⇧⌥ Space"
        case .controlShiftSpace: "⌃⇧ Space"
        case .off: "Off"
        }
    }

    /// Carbon modifier flags, or nil for `.off`.
    var carbonModifiers: UInt32? {
        switch self {
        case .optionSpace: UInt32(optionKey)
        case .controlOptionSpace: UInt32(controlKey | optionKey)
        case .shiftOptionSpace: UInt32(shiftKey | optionKey)
        case .controlShiftSpace: UInt32(controlKey | shiftKey)
        case .off: nil
        }
    }
}

/// System-wide shortcuts via Carbon's RegisterEventHotKey. Unlike an NSEvent global monitor, a hot key
/// *consumes* the keystroke (nothing leaks into the frontmost app) and needs no Accessibility permission.
@MainActor
final class HotKeyCenter {
    enum Key: UInt32 {
        case quickCapture = 1
        /// Registered only while a HUD is on screen, so Esc closes it from anywhere.
        case escape = 2
    }

    static let shared = HotKeyCenter()

    var onPress: (Key) -> Void = { _ in }

    private var refs: [Key: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    private static let signature: OSType = 0x4B4D_4752  // "KMGR"

    /// Returns false if another app already owns the combination.
    @discardableResult
    func register(_ key: Key, keyCode: Int, modifiers: UInt32) -> Bool {
        installHandlerIfNeeded()
        unregister(key)
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: key.rawValue)
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("KarunManager: couldn't register hot key \(key) (status \(status))")
            return false
        }
        refs[key] = ref
        return true
    }

    func unregister(_ key: Key) {
        if let ref = refs.removeValue(forKey: key) { UnregisterEventHotKey(ref) }
    }

    func isRegistered(_ key: Key) -> Bool { refs[key] != nil }

    // MARK: Convenience

    /// Returns false if the shortcut is taken by another app.
    @discardableResult
    func setQuickCapture(_ hotkey: QuickCaptureHotkey) -> Bool {
        guard let modifiers = hotkey.carbonModifiers else {
            unregister(.quickCapture)
            return true
        }
        return register(.quickCapture, keyCode: kVK_Space, modifiers: modifiers)
    }

    func setEscapeActive(_ active: Bool) {
        if active {
            if !isRegistered(.escape) { register(.escape, keyCode: kVK_Escape, modifiers: 0) }
        } else {
            unregister(.escape)
        }
    }

    // MARK: Carbon plumbing

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            guard status == noErr, let key = HotKeyCenter.Key(rawValue: id.id) else { return OSStatus(eventNotHandledErr) }
            // Hot key events are delivered on the main thread's run loop.
            MainActor.assumeIsolated { HotKeyCenter.shared.onPress(key) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
