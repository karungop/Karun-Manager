import KarunManagerCore
import SwiftUI

struct MainWindowView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        let tasks = model.tasks
        // Derived once per render and shared, instead of each pane re-fetching from the store.
        let index = LibraryIndex(tasks: tasks, now: model.now, categories: model.categories)
        HStack(spacing: 0) {
            RibbonView(model: model)
            VLine()
            SidebarView(model: model, tasks: tasks, index: index)
                .frame(width: 240)
            VLine()
            TaskListPane(model: model, tasks: tasks, index: index)
                .frame(minWidth: 440, maxWidth: .infinity)
            VLine()
            InspectorPane(model: model, tasks: tasks, index: index)
                .frame(width: 280)
        }
        .overlay(alignment: .bottomTrailing) {
            StatusBarView(model: model, index: index)
        }
        .background { KeyboardShortcuts(model: model) }
        .background(Theme.bgPrimary)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 1040, minHeight: 600)
    }
}

/// Obsidian's thin far-left icon strip. Traffic lights sit in its top inset.
struct RibbonView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        VStack(spacing: 6) {
            WindowDragArea().frame(height: Theme.titlebarHeight)
            IconButton(symbol: "square.and.pencil", help: "New task (⌘N)") { model.focusComposer() }
            IconButton(symbol: "tray.full", help: "All open tasks", isActive: model.selection == .allOpen) {
                model.selection = .allOpen
            }
            IconButton(symbol: "calendar", help: "Upcoming repeats", isActive: model.selection == .upcoming) {
                model.selection = .upcoming
            }
            IconButton(symbol: "checkmark.circle", help: "Completed", isActive: model.selection == .completed) {
                model.selection = .completed
            }
            Spacer()
            SettingsButton(model: model)
        }
        .frame(width: 44)
        .padding(.bottom, 10)
        .background(Theme.bgSecondary)
    }
}

/// Bottom-right status strip, like Obsidian's word count / sync indicator.
struct StatusBarView: View {
    let model: LibraryModel
    let index: LibraryIndex

    var body: some View {
        TimelineView(.everyMinute) { _ in
            HStack(spacing: 14) {
                Text("\(index.counts[.allOpen] ?? 0) open")
                Text("\(index.counts[.queue(.high)] ?? 0) urgent")
                if let last = model.lastNudgeAt {
                    Text("last nudge \(last, format: .relative(presentation: .named))")
                } else {
                    Text("no nudges yet")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 6)
                    .fill(Theme.bgSecondary)
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 6).strokeBorder(Theme.border))
            )
        }
    }
}

/// Invisible buttons that give the window its key commands: ⌘N new task, ⌘F search, and ⌘1–3,
/// which set the composer's priority while you're typing a new task and otherwise move the selected task.
private struct KeyboardShortcuts: View {
    let model: LibraryModel

    var body: some View {
        ZStack {
            Button("New task") { model.focusComposer() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Search") { model.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
            ForEach(QueueLevel.allCases, id: \.self) { level in
                Button("Priority \(level.title)") {
                    if model.isComposerFocused {
                        model.composerLevel = level
                    } else {
                        model.setQueueOfSelectedTask(to: level)
                    }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(level.rawValue + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SettingsButton: View {
    let model: LibraryModel

    var body: some View {
        IconButton(symbol: "gearshape", help: "Settings (⌘,)") { model.onOpenSettings() }
    }
}
