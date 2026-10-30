# Karun-Manager
Task Manager for my daily life

A macOS menu bar utility with an Obsidian-style main window (macOS 14+, Swift 6, SwiftUI/AppKit, SwiftData)
for frictionless task capture and queue-scheduled nudges. See [`spec.md`](spec.md) for the original MVP specification.

## Build & run

```sh
swift test                      # unit tests (queue rules, repeats, categories, undo snapshots, nudge policy)
scripts/bundle.sh               # → build/KarunManager.app
open build/KarunManager.app     # starts in the menu bar; run `open` again (or click the Dock icon) for the window
```

### Permissions

- **None needed for shortcuts.** Quick Capture and Esc use Carbon hot keys (`RegisterEventHotKey`), which need no
  Accessibility access and swallow the keystroke, so nothing leaks into the app you're typing in.
  You can remove an old "KarunManager" entry from System Settings → Privacy & Security → Accessibility.
- **Notifications need a signed build.** macOS refuses notification permission for ad-hoc signed apps; until then,
  notifications appear as in-app banners (top right). Sign in to Xcode with your Apple ID once (Xcode → Settings →
  Accounts) to get a free "Apple Development" certificate; `scripts/bundle.sh` uses it automatically and prints
  which signature it used.

### Launch flags

| Flag               | Effect                                                                                 |
| ------------------ | -------------------------------------------------------------------------------------- |
| `--demo`           | Throwaway store pre-filled with sample tasks (implies `--in-memory`)                   |
| `--in-memory`      | Throwaway store and settings instead of `~/Library/Application Support/KarunManager`  |
| `--simulate-wake`  | Fires a wake event ~1s after launch                                                    |
| `--simulate-idle`  | Reports 1h idle and runs an idle check                                                 |
| `--simulate-focus` | Like `--simulate-idle` with Terminal frontmost: Distraction Guard badge + notification |
| `--snapshot <dir>` | Debug builds: render the window and HUDs to PNGs, then quit                             |

## How it works

- **Queues:** Urgent / Standard / Someday, each a strict line (numbers on the left). The front task is *Up next*.
  Skipping sends a task to the back of its queue. Per category, skips either **Stay** (never change queue) or
  **Demote** (every N skips, default 5, move it down a queue). Things to do demotes by default; others stay.
  There's no "promote": you only ever skip the Up next task, which is already in the top non-empty queue.
- **Nudges:** a HUD on wake/unlock, or after idle time (defaults: 2 min idle, at most every 10 min). Automatic HUDs are
  *passive*: they float on top but don't take the keyboard. Click one, or press the Quick Capture shortcut, to use it.
  No HUDs while the main window is in front; in focus apps (Settings → Focus apps) you get a badge + notification instead.
- **Tasks** have a title, category, queue, optional notes, due date, repeat rule and snooze. Every task has a hidden
  unique `id`; copies of a repeating task also share a hidden `seriesID`, and a series never has more than one
  unfinished copy. Completing a repeat schedules the next copy on the **Upcoming** page, where it waits (it can't be
  checked off) until its day, unless you choose *Make available now*. Changes in the window can be undone (⌘Z).

## Shortcuts

| Where            | Keys                                                                                                   |
| ---------------- | ------------------------------------------------------------------------------------------------------ |
| Anywhere         | `⌥ Space` (configurable) Quick Capture, or jump into a passive nudge's add-task line                   |
| Any HUD          | `Return` add · `⌘1–3` priority · `⌃1–9` category · `Esc` close (Skip on a nudge you're working in)    |
| Nudge HUD        | `⌘⇧D` done · `⌘S` snooze 1h                                                                            |
| HUD on screen    | `Esc` from another app closes it without counting a skip                                               |
| Main window      | `⌘N` new task · `⌘F` search · `⌘Z` undo · `⌘,` settings · `⌘W` close                                  |
| Task list        | `↑/↓` select · `Space` done · `⌫` delete · `Return` rename · `⌘1–3` move (or composer priority)        |

Prefixes like `buy:`, `call:`, `todo:` or any category's tag name (`work:`) pick the category while typing.

## Layout

- `Sources/KarunManagerCore`: `TaskItem` model, `MLFQ` rules, `TaskStore` (tasks, categories, skip settings, undo
  snapshots), `RepeatRule`, `NudgePolicy`, `SystemEventMonitoring` (live + mock). No UI; unit-tested.
- `Sources/KarunManager`: AppKit/SwiftUI shell: menu bar + status item, `HotKeyCenter`, HUD panels, main window
  (`UI/`), Settings window, notifications (with in-app banner fallback).
