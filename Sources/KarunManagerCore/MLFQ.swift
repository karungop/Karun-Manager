import Foundation

/// Multi-Level Feedback Queue rules (spec §3).
public enum MLFQ {
    public static let promotionThreshold = 5

    /// Lowest `queueLevel` first, then oldest `createdAt` within a level.
    public static func selectNext(
        from tasks: [TaskItem],
        isEligible: (TaskItem) -> Bool = { _ in true }
    ) -> TaskItem? {
        tasks
            .filter { !$0.isCompleted && isEligible($0) }
            .min { ($0.queueLevel, $0.createdAt) < ($1.queueLevel, $1.createdAt) }
    }

    /// Aging: a skipped/dismissed nudge bumps `skipCount`; enough skips promote the task one level.
    public static func recordSkip(_ task: TaskItem) {
        task.skipCount += 1
        if task.skipCount >= promotionThreshold && task.queueLevel > QueueLevel.high.rawValue {
            task.queueLevel -= 1
            task.skipCount = 0
        }
    }
}
