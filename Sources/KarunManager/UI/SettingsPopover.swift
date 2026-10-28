import AppKit
import SwiftUI

struct SettingsPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Notifications")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textNormal)
            ForEach(NotificationSetting.allCases, id: \.self) { setting in
                NotificationToggle(setting: setting)
            }
            HLine()
            Button("Open macOS notification settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.tagText)
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.bgSecondary)
        .environment(\.colorScheme, .dark)
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
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(setting.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textNormal)
                Text(setting.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(Theme.accent)
    }
}
