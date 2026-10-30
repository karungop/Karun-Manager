import Foundation

/// What repeated skips do to a task. Set per category.
///
/// There's deliberately no "promote": a skip only ever happens to the Up next task, which is already in
/// the most important non-empty queue, so moving it up would change nothing.
public enum SkipDirection: String, CaseIterable, Sendable {
    /// Every skip sends it to the back of its line; it never changes queue.
    case stay
    /// Every N skips also move it down a queue, toward Someday.
    case demote

    /// Reads stored values, mapping the retired "promote" to `.stay`.
    public static func stored(_ raw: String) -> SkipDirection? {
        raw == "promote" ? .stay : SkipDirection(rawValue: raw)
    }
}

/// Multi-Level Feedback Queue rules (spec §3).
public enum MLFQ {
    /// Skips before a task changes queue, unless the user changes it (see `TaskStore.skipThreshold`).
    public static let defaultSkipThreshold = 5

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
    /// `threshold` skips instead move it one level in `direction` (to the back of that queue).
    /// A task already at the end of the levels just keeps counting.
    public static func recordSkip(
        _ task: TaskItem,
        direction: SkipDirection = .demote,
        threshold: Int = defaultSkipThreshold,
        at now: Date = Date()
    ) {
        task.skipCount += 1
        task.enqueuedAt = now
        guard task.skipCount >= threshold, let target = nextLevel(for: task, direction: direction) else {
            return
        }
        task.queueLevel = target.rawValue
        task.skipCount = 0
    }

    /// Where the next skip-triggered move would take `task`, or nil if it won't move (Stay, or already Someday).
    public static func nextLevel(for task: TaskItem, direction: SkipDirection) -> QueueLevel? {
        guard direction == .demote else { return nil }
        return QueueLevel(rawValue: task.queueLevel + 1)
    }
}
