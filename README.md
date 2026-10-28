# Karun-Manager
Task Manager for my daily life

A menu bar–only macOS utility (macOS 14+, Swift 6, SwiftUI/AppKit, SwiftData) for frictionless task capture
and MLFQ-scheduled nudges. See [`spec.md`](spec.md) for the full MVP specification.

## Build & run

```sh
swift test                      # unit tests (MLFQ, nudge policy, parser)
scripts/bundle.sh               # → build/KarunManager.app (LSUIElement, ad-hoc signed)
open build/KarunManager.app
```

Grant **Accessibility** access when prompted (System Settings → Privacy & Security → Accessibility);
the global `⌥ Space` monitor receives nothing without it. Ad-hoc signing means you may need to re-grant after rebuilds.

### Simulation flags

```sh
build/KarunManager.app/Contents/MacOS/KarunManager --simulate-wake --in-memory
build/KarunManager.app/Contents/MacOS/KarunManager --simulate-idle --in-memory
```

| Flag              | Effect                                                                     |
| ----------------- | -------------------------------------------------------------------------- |
| `--simulate-wake` | Uses `MockSystemEventMonitor` and fires a wake event ~1s after launch       |
| `--simulate-idle` | Uses `MockSystemEventMonitor` reporting 1h idle and runs an idle check      |
| `--in-memory`     | Throwaway SwiftData store instead of `~/Library/Application Support/KarunManager` |

## Layout

- `Sources/KarunManagerCore` — `TaskItem` model, `MLFQ` rules, `TaskStore`, `NudgePolicy` (triggers + Distraction Guard),
  `SystemEventMonitoring` protocol with live and mock implementations. No UI; fully unit-tested.
- `Sources/KarunManager` — AppKit shell: status item, non-activating `HUDPanel`, Quick Capture and Nudge SwiftUI views, hotkey.

## Shortcuts

- **Quick Capture:** `⌥ Space` toggle · `Return` save · `Esc` cancel. Optional prefixes `buy:` / `call:` / `todo:` set the category.
- **Nudge:** `⌘⇧D` done · `⌘S` snooze 1h · `Esc` skip (5 skips promote the task one queue level).

## Spec interpretation notes

- **Wake:** the spec lists wake as both a Quick Capture trigger and a Nudge trigger. On wake, the app shows the
  Nudge HUD if there's a pending task, otherwise Quick Capture. Distraction Guard applies only to idle triggers, as specified.
- **Snooze** is held in memory (the data model has no snooze field), so it resets on relaunch.
- **Idle polling** runs every 30s; HUDs are never replaced while one is already on screen.
