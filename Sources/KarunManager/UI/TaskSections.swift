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

    /// Queue and category sections accept dropped tasks (moving them there), so they render even when empty.
    var isDropTarget: Bool {
        switch marker {
        case .queue, .category: true
        case .upcoming, .none: false
        }
    }
}

extension SidebarItem {
    /// Queue pages split by category; category pages (and All open) split by priority; Completed by day.
    /// Repeats scheduled for later go in a trailing "Upcoming" section. Rows within a section are in
    /// queue order (the order nudges will come in).
    func sections(from tasks: [TaskItem], now: Date, calendar: Calendar = .current) -> [TaskSection] {
        let visible = tasks.filter(includes)
        if self == .completed {
            return completedSections(visible, now: now, calendar: calendar)
        }

        let available = visible.filter { $0.isAvailable(at: now) }.sorted(by: MLFQ.isOrderedBefore)
        var sections: [TaskSection]
        switch self {
        case .queue:
            let extra = Set(available.map(\.categoryName)).subtracting(TaskCategory.defaults).sorted()
            sections = (TaskCategory.defaults + extra).map { name in
                TaskSection(
                    id: "category-\(name)",
                    title: name,
                    marker: .category(name),
                    tasks: available.filter { $0.categoryName == name }
                )
            }
        default:
            sections = QueueLevel.allCases.map { level in
                TaskSection(
                    id: "queue-\(level.rawValue)",
                    title: level.title,
                    marker: .queue(level),
                    tasks: available.filter { $0.queueLevel == level.rawValue }
                )
            }
        }

        let upcoming = visible
            .filter { !$0.isAvailable(at: now) }
            .sorted { ($0.availableFrom ?? .distantPast) < ($1.availableFrom ?? .distantPast) }
        if !upcoming.isEmpty {
            sections.append(TaskSection(id: "upcoming", title: "Upcoming", marker: .upcoming, tasks: upcoming))
        }
        return sections
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

/// 1-based place in line within each queue, for available open tasks. This is the order nudges use.
func queuePositions(of tasks: [TaskItem], now: Date) -> [UUID: Int] {
    var positions: [UUID: Int] = [:]
    var counts: [Int: Int] = [:]
    for task in tasks.filter({ !$0.isCompleted && $0.isAvailable(at: now) }).sorted(by: MLFQ.isOrderedBefore) {
        counts[task.queueLevel, default: 0] += 1
        positions[task.id] = counts[task.queueLevel]
    }
    return positions
}
