import Foundation
import KarunManagerCore
import UserNotifications

/// Notification types the user can switch on and off (Settings popover in the ribbon).
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
        case .dueReminders: "A reminder at 9 AM on the day a repeat comes back."
        case .queueChanges: "Tell me when enough skips promote or demote a task."
        }
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: key) }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: Dictionary(uniqueKeysWithValues: allCases.map { ($0.key, true) }))
    }
}

/// Posts local notifications and routes their action buttons back into the app.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    enum Action: String, Sendable {
        case done = "DONE"
        case snooze = "SNOOZE"
        case skip = "SKIP"
    }

    private static let taskCategory = "TASK"
    private nonisolated static let taskIDKey = "taskID"
    private static let dueReminderHour = 9

    /// `action` is nil when the notification itself (not a button) was clicked.
    var onResponse: (_ taskID: UUID, _ action: Action?) -> Void = { _, _ in }

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
        center?.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                NSLog("KarunManager: notification authorization failed: \(error)")
            } else if !granted {
                NSLog("KarunManager: notifications are turned off for Karun Manager in System Settings")
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
        deliver(content, id: "nudge-\(task.id)")
    }

    func postQueueChange(for task: TaskItem, from old: QueueLevel, to new: QueueLevel) {
        guard NotificationSetting.queueChanges.isEnabled else { return }
        let content = taskContent(for: task)
        content.title = new.rawValue < old.rawValue ? "Promoted to \(new.title)" : "Demoted to \(new.title)"
        content.body = "\(task.title) was skipped \(MLFQ.promotionThreshold) times."
        content.sound = nil
        deliver(content, id: "queue-\(task.id)-\(Date().timeIntervalSince1970)")
    }

    /// Replaces every scheduled due reminder with one per upcoming repeat. Due reminders are the only
    /// notifications ever left pending (the rest deliver immediately), so a full reset is safe.
    func scheduleDueReminders(for upcoming: [TaskItem]) {
        guard let center else { return }
        center.removeAllPendingNotificationRequests()
        guard NotificationSetting.dueReminders.isEnabled else { return }

        let calendar = Calendar.current
        for task in upcoming {
            guard let day = task.availableFrom,
                  let fireDate = calendar.date(bySettingHour: Self.dueReminderHour, minute: 0, second: 0, of: day),
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

    private func deliver(_ content: UNNotificationContent, id: String) {
        center?.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
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
