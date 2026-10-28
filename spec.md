# Product Specification: macOS Context-Aware Task Engine (MVP)

## 1. Executive Summary

An unlisted, lightweight macOS menu bar utility (`LSUIElement = true`) that provides frictionless task capture and intelligent task nudging using system event monitoring and a Multi-Level Feedback Queue (MLFQ) scheduling engine.

## 2. Technical Stack & Architecture

- **Language & Frameworks:** Swift 6, SwiftUI, AppKit
- **Minimum Target:** macOS 14.0+
- **Persistence:** SwiftData
- **Architecture:** Protocol-oriented MVVM + Dependency Injection (for system event mocking)

## 3. Data Model Specification

### `TaskItem` Entity

| Field          | Type             | Notes                                                                     |
| -------------- | ---------------- | ------------------------------------------------------------------------- |
| `id`           | `UUID`           | Unique attribute                                                          |
| `title`        | `String`         |                                                                           |
| `categoryName` | `String`         | Default categories: "Things to do", "Things to buy", "People to call"     |
| `queueLevel`   | `Int`            | 0 = High/Urgent, 1 = Medium/Standard, 2 = Low/Someday                     |
| `skipCount`    | `Int`            | Tracks skipped or dismissed nudges                                        |
| `createdAt`    | `Date`           |                                                                           |
| `isCompleted`  | `Bool`           |                                                                           |
| `completedAt`  | `Date?`          | Optional                                                                  |

### MLFQ & Aging Engine Rules

**Task Selection Strategy:** When triggering a nudge, always select the top task ordered by:

1. Lowest `queueLevel` (0 before 1, 1 before 2).
2. Oldest `createdAt` timestamp within the same queue level.

**Aging Formula:**

- Every time a task is presented in a nudge HUD and dismissed or skipped without completion, increment `skipCount` by 1.
- **Promotion Rule:** IF `skipCount >= 5` AND `queueLevel > 0`:
  - Set `queueLevel = queueLevel - 1` (promotes task to higher priority).
  - Reset `skipCount = 0`.
- **Amendment — per-category skip direction:** each category is set to *promote* (rule above) or *demote*
  (`queueLevel + 1`, capped at 2). Defaults: "Things to do" demotes; "Things to buy" and "People to call" promote.

## 4. Feature Specifications

### Feature A: Status Bar Anchor & Quick Capture HUD

- **Application Type:** Background utility (`LSUIElement = true` in `Info.plist`).
- **Menu Bar Icon:** `NSStatusItem` displaying a subtle SF Symbol (e.g., `checkmark.square`).
- **Floating HUD (`NSPanel`):**
  - Panel must use `.nonactivatingPanel` style and `.floating` level so it stays visible without stealing key window focus from active apps.
  - Positioned top-center of the main display screen.
  - Displays a single input field: "What's on your mind?"
- **Shortcuts:**
  - `Return`: Saves task to SwiftData (default `queueLevel = 1`) and closes HUD (`orderOut`).
  - `Esc`: Closes HUD immediately without saving.
- **Global Hotkey:** Listens globally for `Option + Space` via `NSEvent.addGlobalMonitorForEvents` to toggle Quick Capture HUD.

### Feature B: System Event & Idle Monitoring

- **Abstraction Layer:** Define `SystemEventMonitoring` protocol wrapping macOS system queries to allow CLI/unit testing mocking (`--simulate-wake`, `--simulate-idle`).
- **Wake Listener:** Register for `NSWorkspace.screensDidWakeNotification` and `com.apple.screenIsUnlocked`.
- **Action on Wake:** Display Quick Capture HUD automatically.
- **Idle Monitor:** Query global input idle time using `CGEventSource.secondsSinceLastEventType(.combinedSessionState, .userInputEvent)`.
- **Nudge Triggers:** Trigger a Nudge HUD when EITHER:
  - System wakes/unlocks.
  - `timeSinceLastNudge >= 600s` (10 minutes) AND `systemIdleTime >= 120s` (2 minutes).

### Feature C: Distraction Guard (App Blocklist)

- **Active App Query:** Query active application using `NSWorkspace.shared.frontmostApplication.bundleIdentifier`.
- **Default Blocklist:** `["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.apple.Terminal", "com.googlecode.iterm2", "md.obsidian"]`.
- **Guard Behavior:** If the frontmost bundle ID matches the blocklist when an Idle trigger fires, suppress the screen-takeover HUD and update the MenuBar icon badge quietly instead.

### Feature D: Interactive Nudge HUD UI

- **Components:**
  - Banner showing: `[Category] Top Task Title`
  - Actions: `[ Done (Cmd+Shift+D) ] | [ Snooze 1hr (Cmd+S) ] | [ Skip (Esc) ]`
- **Keyboard Navigation:**
  - `Cmd + Shift + D`: Mark task `isCompleted = true`, set `completedAt = Date()`, close panel.
  - `Cmd + S`: Defer task nudge for 3600 seconds, close panel.
  - `Esc`: Close panel, increment task `skipCount` by 1, evaluate MLFQ promotion.

## 5. Verification & Acceptance Criteria

- [ ] App compiles with zero warnings under Swift 6 strict concurrency mode.
- [ ] App runs in MenuBar without appearing in Dock or Application Switcher (`Cmd + Tab`).
- [ ] Pressing `Option + Space` invokes HUD within < 100ms.
- [ ] Simulating wake via mock CLI flag reliably opens HUD without crashing or stealing focus.
- [ ] Skipping a task 5 times successfully updates `queueLevel` from 1 to 0 in SwiftData.
