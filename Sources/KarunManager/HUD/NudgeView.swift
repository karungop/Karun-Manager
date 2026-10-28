import KarunManagerCore
import SwiftUI

struct NudgeView: View {
    let task: TaskItem
    let onDone: () -> Void
    let onSnooze: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Up next", systemImage: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    QueueBadge(level: QueueLevel(task: task))
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
                    Text("skipped \(task.skipCount)/\(MLFQ.promotionThreshold)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                }
                Button(action: onSkip) {
                    HStack(spacing: 8) { Text("Skip"); KbdChip(keys: "esc") }
                }
                .buttonStyle(ObsidianButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .hudChrome()
    }
}
