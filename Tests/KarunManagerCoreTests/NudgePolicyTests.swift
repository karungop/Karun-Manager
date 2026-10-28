import Foundation
import Testing
@testable import KarunManagerCore

struct NudgePolicyTests {
    let policy = NudgePolicy()
    let now = Date(timeIntervalSince1970: 10_000)

    private func idle(
        lastNudgeAgo: TimeInterval? = nil,
        idleTime: TimeInterval = 120,
        frontmost: String? = "com.apple.Safari",
        hasPendingTask: Bool = true
    ) -> NudgeDecision {
        policy.evaluate(
            .idleTick,
            now: now,
            lastNudgeAt: lastNudgeAgo.map { now.addingTimeInterval(-$0) },
            idleTime: idleTime,
            frontmostBundleID: frontmost,
            hasPendingTask: hasPendingTask
        )
    }

    @Test func idleNudgeRequiresBothThresholds() {
        #expect(idle(lastNudgeAgo: 600, idleTime: 120) == .showNudge)
        #expect(idle(lastNudgeAgo: 599, idleTime: 120) == .none)
        #expect(idle(lastNudgeAgo: 600, idleTime: 119) == .none)
        #expect(idle(lastNudgeAgo: nil, idleTime: 120) == .showNudge)
    }

    @Test func idleNudgeNeedsATask() {
        #expect(idle(hasPendingTask: false) == .none)
    }

    @Test(arguments: Array(NudgePolicy.defaultBlocklist))
    func distractionGuardBadgesInsteadOfShowing(bundleID: String) {
        #expect(idle(frontmost: bundleID) == .badgeOnly)
    }

    @Test func wakeShowsNudgeOrCaptureEvenInBlocklistedApp() {
        let withTask = policy.evaluate(.wake, now: now, lastNudgeAt: now, idleTime: 0,
                                       frontmostBundleID: "com.apple.dt.Xcode", hasPendingTask: true)
        let empty = policy.evaluate(.wake, now: now, lastNudgeAt: now, idleTime: 0,
                                    frontmostBundleID: nil, hasPendingTask: false)
        #expect(withTask == .showNudge)
        #expect(empty == .showQuickCapture)
    }

    @MainActor
    @Test func mockMonitorDeliversWake() {
        let mock = MockSystemEventMonitor()
        var woke = false
        mock.startObservingWake { woke = true }
        mock.simulateWake()
        #expect(woke)
    }
}

struct CaptureParserTests {
    @Test func parsesCategoryPrefixes() {
        #expect(CaptureParser.parse("buy: oat milk")! == ("oat milk", TaskCategory.thingsToBuy))
        #expect(CaptureParser.parse("Call: Mom")! == ("Mom", TaskCategory.peopleToCall))
        #expect(CaptureParser.parse("  water plants ")! == ("water plants", TaskCategory.thingsToDo))
        #expect(CaptureParser.parse("note: unknown prefix")! == ("note: unknown prefix", TaskCategory.thingsToDo))
        #expect(CaptureParser.parse("   ") == nil)
    }

    @Test func parsesLaunchFlags() {
        let options = LaunchOptions(arguments: ["KarunManager", "--simulate-wake", "--in-memory"])
        #expect(options.simulateWake && options.inMemory && !options.simulateIdle)
        #expect(options.usesMockMonitor)
    }
}
