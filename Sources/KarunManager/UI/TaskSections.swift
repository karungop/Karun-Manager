import Foundation
import KarunManagerCore

/// A subheading on a list page plus the tasks under it.
struct TaskSection: Identifiable {
    enum Marker {
        case queue(QueueLevel)
        case category(String)
        case upcoming
        case none
    }

    let id: String
    let title: String
    let marker: Marker
    let tasks: [TaskItem]

    var isUpcoming: Bool {
        if case .upcoming = marker { return true }
        return false
    }

    /// Queue and category sections accept dropped tasks (moving them there), so they render even when empty.
    var isDropTarget: Bool {
        switch marker {
        case .queue, .category: true
        case .upcoming, .none: false
        }
    }
}

extension SidebarItem {
    /// Queue pages split by category; category pages (and All open) split by priority; Upcoming and
    /// Completed by date. Rows within a queue section are in queue order (the order nudges come in).
    func sections(
        from tasks: [TaskItem],
        now: Date,
        categories: [String],
        search: String = "",
        calendar: Calendar = .current
    ) -> [TaskSection] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let visible = tasks.filter { task in
            includes(task, now: now) && (query.isEmpty
                || task.title.localizedCaseInsensitiveContains(query)
                || (task.notes ?? "").localizedCaseInsensitiveContains(query))
        }
        switch self {
        case .completed:
            return completedSections(visible, now: now, calendar: calendar)
        case .upcoming:
            return upcomingSections(visible, now: now, calendar: calendar)
        default:
            break
        }

        let line = visible.sorted(by: MLFQ.isOrderedBefore)
        var sections: [TaskSection]
        if case .queue = self {
            let extra = Set(line.map(\.categoryName)).subtracting(categories).sorted()
            sections = (categories + extra).map { name in
                TaskSection(
                    id: "category-\(name)",
                    title: name,
                    marker: .category(name),
                    tasks: line.filter { $0.categoryName == name }
                )
            }
        } else {
            sections = QueueLevel.allCases.map { level in
                TaskSection(
                    id: "queue-\(level.rawValue)",
                    title: level.title,
                    marker: .queue(level),
                    tasks: line.filter { $0.queueLevel == level.rawValue }
                )
            }
        }
        // Empty sections stay visible as drop targets, except while searching.
        if !query.isEmpty { sections.removeAll { $0.tasks.isEmpty } }
        return sections
    }

    private func upcomingSections(_ tasks: [TaskItem], now: Date, calendar: Calendar) -> [TaskSection] {
        let soonestFirst = tasks.sorted { ($0.availableFrom ?? .distantPast) < ($1.availableFrom ?? .distantPast) }
        let buckets = ["Tomorrow", "This week", "Later"]
        let grouped = Dictionary(grouping: soonestFirst) { task -> String in
            guard let day = task.availableFrom else { return "Later" }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
               calendar.isDate(day, inSameDayAs: tomorrow) || day < tomorrow { return "Tomorrow" }
            if let week = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)), day < week {
                return "This week"
            }
            return "Later"
        }
        return buckets.compactMap { bucket in
            guard let tasks = grouped[bucket] else { return nil }
            return TaskSection(id: "upcoming-\(bucket)", title: bucket, marker: .upcoming, tasks: tasks)
        }
    }

    private func completedSections(_ tasks: [TaskItem], now: Date, calendar: Calendar) -> [TaskSection] {
        let newestFirst = tasks.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let grouped = Dictionary(grouping: newestFirst) { task in
            Self.completionBucket(task.completedAt, calendar: calendar, now: now)
        }
        return ["Today", "Yesterday", "This week", "Earlier"].compactMap { bucket in
            guard let tasks = grouped[bucket] else { return nil }
            return TaskSection(id: "done-\(bucket)", title: bucket, marker: .none, tasks: tasks)
        }
    }

    private static func completionBucket(_ date: Date?, calendar: Calendar, now: Date) -> String {
        guard let date else { return "Earlier" }
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date > weekAgo { return "This week" }
        return "Earlier"
    }
}
