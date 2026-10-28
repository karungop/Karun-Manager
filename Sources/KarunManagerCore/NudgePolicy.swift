import Foundation

public enum NudgeTrigger: Sendable {
    case wake
    case idleTick
}

public enum NudgeDecision: Equatable, Sendable {
    case none
    case showQuickCapture
    case showNudge
    /// Distraction Guard: a nudge is due but the user is in a focus app.
    case badgeOnly
}

/// Decides what (if anything) to show for a trigger (spec §4B–C). Pure, so it's trivially testable.
public struct NudgePolicy: Sendable {
    public static let defaultBlocklist: Set<String> = [
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "md.obsidian",
    ]

    public var nudgeInterval: TimeInterval
    public var idleThreshold: TimeInterval
    public var blocklist: Set<String>

    public init(
        nudgeInterval: TimeInterval = 600,
        idleThreshold: TimeInterval = 120,
        blocklist: Set<String> = NudgePolicy.defaultBlocklist
    ) {
        self.nudgeInterval = nudgeInterval
        self.idleThreshold = idleThreshold
        self.blocklist = blocklist
    }

    public func evaluate(
        _ trigger: NudgeTrigger,
        now: Date,
        lastNudgeAt: Date?,
        idleTime: TimeInterval,
        frontmostBundleID: String?,
        hasPendingTask: Bool
    ) -> NudgeDecision {
        switch trigger {
        case .wake:
            // Waking is a natural checkpoint: surface the top task, or invite capture if the queue is empty.
            return hasPendingTask ? .showNudge : .showQuickCapture

        case .idleTick:
            guard hasPendingTask else { return .none }
            let sinceLast = lastNudgeAt.map { now.timeIntervalSince($0) } ?? .infinity
            guard sinceLast >= nudgeInterval, idleTime >= idleThreshold else { return .none }
            if let frontmostBundleID, blocklist.contains(frontmostBundleID) { return .badgeOnly }
            return .showNudge
        }
    }
}
