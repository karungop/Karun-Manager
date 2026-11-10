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

### iCloud sync

Tasks (SwiftData mirrored to your private CloudKit database) and preferences (categories, skip rules, nudge timing,
via iCloud key-value storage) sync between Macs signed in to the same Apple ID. The Quick Capture shortcut and Open at
login stay per-Mac. Settings → iCloud shows whether sync is on.

Sync needs a **paid Apple Developer account**, because iCloud entitlements only work with a provisioning profile:

1. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources), register the App ID
   `com.karungopal.KarunManager` with the **iCloud** (CloudKit) and **Push Notifications** capabilities, and create
   the container `iCloud.com.karungopal.KarunManager`.
2. Register your Mac, then create a **macOS App Development** profile for that App ID and download it.
3. Build with it: `KARUNMANAGER_PROFILE=~/Downloads/KarunManager.provisionprofile scripts/bundle.sh`

Without `KARUNMANAGER_PROFILE` the app is signed without the entitlements and keeps everything on this Mac (signing
with them but no profile would stop macOS from launching it). Your existing tasks upload on the first synced launch.
Development builds use CloudKit's development environment, which creates the schema automatically; before shipping a
Developer ID build, deploy the schema to production in the CloudKit Console.

When two Macs edit while offline, iCloud keeps the last write per task. Afterwards the app merges duplicates: one
copy per task `id` and one unfinished copy per repeating series.

### iPhone app

A small companion in `iOS/` (iOS 17+). It shows your open tasks by queue and lets you **add** (with the same `buy:` /
`call:` / `work:` prefixes), **complete** (tap the circle or swipe right) and **delete** (swipe left) them, with a few
seconds to undo. Everything else stays on the Mac: categories, skip rules, nudges, repeats, due dates, snooze and
settings. The phone shows them but can't change them. Scheduled repeats stay hidden until their day, as on the Mac.

It uses the same `KarunManagerCore` library, the same bundle ID and the same iCloud container, so with sync on both
apps share one task list.

```sh
open iOS/KarunManagerMobile.xcodeproj           # then pick an iPhone simulator and Run
xcodebuild -project iOS/KarunManagerMobile.xcodeproj -scheme KarunManagerMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17' test   # UI tests: add, complete, delete, undo
```

To run it on your iPhone, copy `iOS/Config/Local.xcconfig.example` to `iOS/Config/Local.xcconfig` (gitignored) and set
your `DEVELOPMENT_TEAM`. Keep its two iCloud lines to sync with the Mac. This needs the paid account and App ID from
*iCloud sync* above, with the iPhone registered too. Delete those two lines to keep tasks on the phone only (a free
account works for that). The cloud icon in the top right shows which mode you're in. Add `--demo` in the scheme's
Run arguments for sample tasks.

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
  `id` (unique in practice; CloudKit forbids enforcing it, so sync repair merges duplicates); copies of a repeating task also share a hidden `seriesID`, and a series never has more than one
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
