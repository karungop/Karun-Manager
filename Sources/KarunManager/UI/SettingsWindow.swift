import AppKit
import SwiftUI

/// A standard Settings window (⌘, / the ribbon gear), styled like the rest of the app.
@MainActor
final class SettingsWindowController {
    private let model: LibraryModel
    private var window: NSWindow?

    init(model: LibraryModel) {
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        model.settings.refreshLaunchAtLoginStatus()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.windowBackground
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(model: model, settings: model.settings))
        window.center()
        return window
    }
}

struct SettingsView: View {
    @Bindable var model: LibraryModel
    @Bindable var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Settings")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textNormal)
                    .padding(.top, 18)
                general
                nudges
                FocusAppsSection(settings: settings)
                notifications
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bgPrimary)
        .environment(\.colorScheme, .dark)
    }

    private var general: some View {
        SettingsSection("General") {
            SettingsRow("Quick Capture shortcut", detail: hotkeyDetail) {
                Menu(settings.quickCaptureHotkey.title) {
                    ForEach(QuickCaptureHotkey.allCases, id: \.self) { option in
                        Button(option.title) { settings.quickCaptureHotkey = option }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if settings.quickCaptureHotkeyTaken {
                Label(
                    "Another app (often Alfred, Raycast or ChatGPT) already uses \(settings.quickCaptureHotkey.title). Pick a different shortcut, or free it in that app.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
            SettingsRow("Open at login", detail: launchDetail) {
                Toggle("", isOn: Binding(
                    get: { settings.launchesAtLogin },
                    set: { settings.setLaunchesAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .labelsHidden()
            }
        }
    }

    private var hotkeyDetail: String {
        "Opens Quick Capture from any app, or focuses the add-task field when this window is in front."
    }

    private var launchDetail: String {
        switch settings.launchAtLoginStatus {
        case .requiresApproval: "Waiting for approval in System Settings → General → Login Items."
        case .enabled: "Karun Manager starts quietly in the menu bar when you log in."
        default: "Start quietly in the menu bar when you log in."
        }
    }

    private var nudges: some View {
        SettingsSection("Nudges") {
            SettingsRow("Time between idle nudges", detail: "At most one idle nudge in this window.") {
                StepperValue(value: $settings.nudgeIntervalMinutes, range: 5...120, step: 5, unit: "min")
            }
            SettingsRow("Idle time before a nudge", detail: "No keyboard or mouse input for this long.") {
                StepperValue(value: $settings.idleThresholdMinutes, range: 1...30, step: 1, unit: "min")
            }
            SettingsRow("Skips before a task moves down", detail: "Only for categories set to Demote; Stay categories never change queue.") {
                StepperValue(
                    value: Binding(get: { model.skipThreshold }, set: { model.setSkipThreshold($0) }),
                    range: 2...20,
                    step: 1,
                    unit: "skips"
                )
            }
        }
    }

    private var notifications: some View {
        SettingsSection("Notifications") {
            ForEach(NotificationSetting.allCases, id: \.self) { setting in
                NotificationToggle(setting: setting)
            }
            SettingsRow("Reminder time", detail: "When “due today” reminders for repeats go out.") {
                StepperValue(value: $settings.dueReminderHour, range: 0...23, step: 1, unit: nil) { hour in
                    let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
                    return date.formatted(.dateTime.hour())
                }
            }
            if !model.usesSystemNotifications {
                Label(
                    "macOS blocked system notifications for this build (it isn't signed with a developer certificate), so these appear as in-app banners in the top-right corner.",
                    systemImage: "info.circle"
                )
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open macOS notification settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.tagText)
        }
    }
}

// MARK: - Focus apps

private struct FocusAppsSection: View {
    @Bindable var settings: AppSettings

    private var addableApps: [NSRunningApplication] {
        let current = Set(settings.focusApps)
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { app in
                guard let id = app.bundleIdentifier, !current.contains(id), id != Bundle.main.bundleIdentifier else {
                    return false
                }
                return seen.insert(id).inserted
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        SettingsSection("Focus apps") {
            Text("While one of these is in front, idle nudges become a menu-bar badge and a quiet notification instead of a HUD.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(settings.focusApps, id: \.self) { bundleID in
                    FocusAppRow(bundleID: bundleID) {
                        settings.focusApps.removeAll { $0 == bundleID }
                    }
                    if bundleID != settings.focusApps.last { HLine() }
                }
                if settings.focusApps.isEmpty {
                    Text("No focus apps — idle nudges always show the HUD.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textFaint)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bgSecondary))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
            Menu("Add a running app…") {
                ForEach(addableApps, id: \.processIdentifier) { app in
                    Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                        if let id = app.bundleIdentifier { settings.focusApps.append(id) }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(Theme.tagText)
        }
    }
}

private struct FocusAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    private var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    var body: some View {
        HStack(spacing: 10) {
            if let url = appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed").frame(width: 20, height: 20).foregroundStyle(Theme.textFaint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(appURL.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textNormal)
                Text(bundleID)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textFaint)
            }
            Spacer()
            HUDCloseButton(help: "Remove", action: onRemove)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

// MARK: - Building blocks

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textNormal)
            content
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let control: Control

    init(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textNormal)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
    }
}

/// "− 10 min +"
private struct StepperValue: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String?
    var format: ((Int) -> String)?

    init(value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String?, format: ((Int) -> String)? = nil) {
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.format = format
    }

    var body: some View {
        HStack(spacing: 8) {
            stepButton("minus", delta: -step)
            Text(format?(value) ?? "\(value)\(unit.map { " \($0)" } ?? "")")
                .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textNormal)
                .frame(minWidth: 62)
            stepButton("plus", delta: step)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        Button {
            value = min(max(value + delta, range.lowerBound), range.upperBound)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textMuted)
    }
}

private struct NotificationToggle: View {
    let setting: NotificationSetting
    @AppStorage private var isOn: Bool

    init(setting: NotificationSetting) {
        self.setting = setting
        _isOn = AppStorage(wrappedValue: true, setting.key)
    }

    var body: some View {
        SettingsRow(setting.title, detail: setting.detail) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .labelsHidden()
        }
    }
}
