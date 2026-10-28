import KarunManagerCore
import SwiftUI

struct NudgeView: View {
    let task: TaskItem
    let skipDirection: SkipDirection
    let onDone: () -> Void
    let onSnooze: () -> Void
    let onSkip: () -> Void
    /// Saves a new task without closing the HUD; returns false for empty input.
    let onAdd: (String) -> Bool

    @State private var draft = ""
    @State private var addedCount = 0
    @FocusState private var isCaptureFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Up next", systemImage: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    QueueBadge(level: QueueLevel(task: task))
                    HUDCloseButton(help: "Skip (esc)", action: onSkip)
                        .padding(.leading, 6)
                }
                Text(task.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.textNormal)
                    .lineLimit(2)
                TagPill(categoryName: task.categoryName)
            }
            .padding(18)

            HLine()

            HStack(spacing: 8) {
                Button(action: onDone) {
                    HStack(spacing: 8) { Text("Done"); KbdChip(keys: "⌘⇧D") }
                }
                .buttonStyle(ObsidianButtonStyle(prominent: true))
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button(action: onSnooze) {
                    HStack(spacing: 8) { Text("Snooze 1h"); KbdChip(keys: "⌘S") }
                }
                .buttonStyle(ObsidianButtonStyle())
                .keyboardShortcut("s", modifiers: .command)

                Spacer()

                if task.skipCount > 0 {
                    Label("skipped \(task.skipCount)/\(MLFQ.promotionThreshold)", systemImage: skipDirection.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                        .help(skipDirection.explanation)
                }
                Button(action: onSkip) {
                    HStack(spacing: 8) { Text("Skip"); KbdChip(keys: "esc") }
                }
                .buttonStyle(ObsidianButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            HLine()
            captureLine
        }
        .hudChrome()
        .onAppear { isCaptureFocused = true }
    }

    /// Quick Capture inside the nudge, so a wake/idle HUD can take new tasks without opening the app.
    private var captureLine: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isCaptureFocused ? Theme.accent : Theme.textFaint)
            TextField(
                "",
                text: $draft,
                prompt: Text("Add a task…  (buy:  call:  todo:)").foregroundStyle(Theme.textFaint)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(Theme.textNormal)
            .focused($isCaptureFocused)
            .onSubmit {
                guard onAdd(draft) else { return }
                draft = ""
                addedCount += 1
            }
            .onExitCommand(perform: onSkip)
            if addedCount > 0 {
                Label("\(addedCount) added", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.green)
                    .transition(.opacity)
            }
            KbdChip(keys: "↩")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Color.black.opacity(0.12))
    }
}
