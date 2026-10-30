import Foundation
import KarunManagerCore
import UserNotifications

/// Notification types the user can switch on and off (Settings window).
enum NotificationSetting: String, CaseIterable {
    case nudges
    case dueReminders
    case queueChanges

    var key: String { "notifications.\(rawValue)" }

    var title: String {
        switch self {
        case .nudges: "Nudges while you're focused"
        case .dueReminders: "Repeating task is due"
        case .queueChanges: "Skips move a task"
        }
    }

    var detail: String {
        switch self {
        case .nudges: "When the Distraction Guard holds back the HUD, send a quiet notification with Done / Snooze / Skip."
        case .dueReminders: "A reminder on the day a repeat comes back."
        case .queueChanges: "Tell me when enough skips move a task down a queue."
        }
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: key) }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: Dictionary(uniqueKeysWithValues: allCases.map { ($0.key, true) }))
    }
}

/// Posts local notifications and routes their action buttons back into the app. If macOS refuses
/// authorization (ad-hoc signed builds), everything falls back to in-app banners via `ToastPresenter`.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    enum Action: String, Sendable {
        case done = "DONE"
        case snooze = "SNOOZE"
        case skip = "SKIP"
    }

    private static let taskCategory = "TASK"
    private nonisolated static let taskIDKey = "taskID"
    /// Hour of day for due reminders (set from AppSettings).
    var dueReminderHour = 9

    /// `action` is nil when the notification itself (not a button) was clicked.
    var onResponse: (_ taskID: UUID, _ action: Action?) -> Void = { _, _ in }
    /// Reports whether system notifications are available (true) or banners are in use (false).
    var onAvailabilityChange: (Bool) -> Void = { _ in }

    private(set) var usesSystemNotifications = false
    private let toasts = ToastPresenter()
    /// Due reminders already shown as banners, so a relaunch doesn't repeat them.
    private var announcedDueIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "notifications.announcedDue") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "notifications.announcedDue") }
    }

    /// UNUserNotificationCenter traps without a bundle identifier, e.g. under a bare `swift run`.
    private let center: UNUserNotificationCenter?

    override init() {
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
        guard let center else { return }
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: Action.done.rawValue, title: "Done"),
            UNNotificationAction(identifier: Action.snooze.rawValue, title: "Snooze 1h"),
            UNNotificationAction(identifier: Action.skip.rawValue, title: "Skip"),
        ]
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.taskCategory, actions: actions, intentIdentifiers: []),
        ])
    }

    func requestAuthorization() {
        guard let center else {
            onAvailabilityChange(false)
            return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                NSLog("KarunManager: system notifications unavailable, using in-app banners: \(error)")
            }
            Task { @MainActor in
                self.usesSystemNotifications = granted
                self.onAvailabilityChange(granted)
            }
        }
    }

    // MARK: Posting

    func postNudge(for task: TaskItem) {
        guard NotificationSetting.nudges.isEnabled else { return }
        let content = taskContent(for: task)
        content.title = "Up next"
        content.body = task.title
        content.subtitle = task.categoryName
        deliver(content, id: "nudge-\(task.id)", taskID: task.id, hasTaskActions: true)
    }

    func postQueueChange(for task: TaskItem, from old: QueueLevel, to new: QueueLevel, threshold: Int) {
        guard NotificationSetting.queueChanges.isEnabled else { return }
        let content = taskContent(for: task)
        content.title = "Moved down to \(new.title)"
        content.body = "\(task.title) was skipped \(threshold) times."
        content.sound = nil
        deliver(content, id: "queue-\(task.id)-\(Date().timeIntervalSince1970)", taskID: task.id, hasTaskActions: false)
    }

    /// Replaces every scheduled due reminder with one per upcoming repeat. Due reminders are the only
    /// notifications ever left pending (the rest deliver immediately), so a full reset is safe.
    func scheduleDueReminders(for upcoming: [TaskItem]) {
        guard usesSystemNotifications, let center else { return }
        center.removeAllPendingNotificationRequests()
        guard NotificationSetting.dueReminders.isEnabled else { return }

        let calendar = Calendar.current
        for task in upcoming {
            guard let day = task.availableFrom,
                  let fireDate = calendar.date(bySettingHour: dueReminderHour, minute: 0, second: 0, of: day),
                  fireDate > Date() else { continue }
            let content = taskContent(for: task)
            content.title = "Due today"
            content.body = task.title
            content.subtitle = "\(task.categoryName) · repeats \(task.repeatRule.title.lowercased())"
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: "due-\(task.id)", content: content, trigger: trigger))
        }
    }

    private func taskContent(for task: TaskItem) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.taskCategory
        content.userInfo = [Self.taskIDKey: task.id.uuidString]
        content.threadIdentifier = task.categoryName
        content.sound = .default
        return content
    }

    /// Banner-mode stand-in for scheduled due reminders, run on the app's 30s tick: announces each
    /// repeat once, on or after 9 AM of the day it comes back.
    func announceDueTasksIfNeeded(_ open: [TaskItem], now: Date = Date()) {
        guard !usesSystemNotifications, NotificationSetting.dueReminders.isEnabled else { return }
        let calendar = Calendar.current
        var announced = announcedDueIDs
        for task in open where task.repeatRule != .never {
            guard let day = task.availableFrom, !announced.contains(task.id.uuidString),
                  calendar.isDate(day, inSameDayAs: now),
                  let fireDate = calendar.date(bySettingHour: dueReminderHour, minute: 0, second: 0, of: day),
                  now >= fireDate else { continue }
            announced.insert(task.id.uuidString)
            let content = taskContent(for: task)
            content.title = "Due today"
            content.body = task.title
            content.subtitle = "\(task.categoryName) · repeats \(task.repeatRule.title.lowercased())"
            deliver(content, id: "due-\(task.id)", taskID: task.id, hasTaskActions: true)
        }
        announcedDueIDs = announced
    }

    private func deliver(_ content: UNNotificationContent, id: String, taskID: UUID, hasTaskActions: Bool) {
        guard usesSystemNotifications, let center else {
            let toast = ToastPresenter.Toast(
                title: content.title,
                subtitle: content.subtitle.isEmpty ? nil : content.subtitle,
                body: content.body,
                hasTaskActions: hasTaskActions
            )
            toasts.show(toast) { [weak self] action in self?.onResponse(taskID, action) }
            return
        }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error { NSLog("KarunManager: failed to deliver notification \(id): \(error)") }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let idString = info[Self.taskIDKey] as? String, let id = UUID(uuidString: idString) else { return }
        let action = Action(rawValue: response.actionIdentifier)
        await MainActor.run { self.onResponse(id, action) }
    }
}
