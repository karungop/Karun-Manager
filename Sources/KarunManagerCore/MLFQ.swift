import Foundation

/// Which way repeated skips move a task. Set per category.
public enum SkipDirection: String, CaseIterable, Sendable {
    /// Toward Urgent: ignoring it makes it louder (spec default).
    case promote
    /// Toward Someday: ignoring it means it matters less.
    case demote
}

/// Multi-Level Feedback Queue rules (spec §3).
public enum MLFQ {
    public static let promotionThreshold = 5

    /// The one ordering everything uses: lowest `queueLevel` first, then front of the line
    /// (`queuePosition`) within a level. `createdAt` breaks exact ties.
    public static func isOrderedBefore(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        (lhs.queueLevel, lhs.queuePosition, lhs.createdAt) < (rhs.queueLevel, rhs.queuePosition, rhs.createdAt)
    }

    public static func selectNext(
        from tasks: [TaskItem],
        isEligible: (TaskItem) -> Bool = { _ in true }
    ) -> TaskItem? {
        tasks
            .filter { !$0.isCompleted && isEligible($0) }
            .min(by: isOrderedBefore)
    }

    /// Aging: a skipped/dismissed nudge bumps `skipCount` and sends the task to the back of its queue.
    /// Enough skips instead move it one level in `direction` (to the back of that queue).
    /// A task already at the end of the levels just keeps counting.
    public static func recordSkip(_ task: TaskItem, direction: SkipDirection = .promote, at now: Date = Date()) {
        task.skipCount += 1
        task.enqueuedAt = now
        guard task.skipCount >= promotionThreshold, let target = nextLevel(for: task, direction: direction) else {
            return
        }
        task.queueLevel = target.rawValue
        task.skipCount = 0
    }

    /// Where the next skip-triggered move would take `task`, or nil if it's already at the end.
    public static func nextLevel(for task: TaskItem, direction: SkipDirection) -> QueueLevel? {
        let step = direction == .promote ? -1 : 1
        return QueueLevel(rawValue: task.queueLevel + step)
    }
}
