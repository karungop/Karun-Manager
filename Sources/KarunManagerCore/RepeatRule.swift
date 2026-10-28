import Foundation

/// How a task recurs. Completing a repeating task schedules a fresh copy for the next occurrence.
public enum RepeatRule: String, CaseIterable, Sendable {
    case never
    case daily
    case weekdays
    case weekly
    case biweekly
    case monthly
    case yearly

    /// Start of the day the next occurrence becomes available, counting from `date`.
    public func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: date)
        switch self {
        case .never:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: today)
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: today)
            while let candidate = next, calendar.isDateInWeekend(candidate) {
                next = calendar.date(byAdding: .day, value: 1, to: candidate)
            }
            return next
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: today)
        case .biweekly:
            return calendar.date(byAdding: .day, value: 14, to: today)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: today)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: today)
        }
    }
}
