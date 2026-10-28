import KarunManagerCore
import SwiftUI

/// Right sidebar: what the next nudge will show, plus Obsidian-style "Properties" for the selected task.
struct InspectorPane: View {
    @Bindable var model: LibraryModel
    let tasks: [TaskItem]

    private var selectedTask: TaskItem? {
        tasks.first { $0.id == model.selectedTaskID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Inspector")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.leading, 16)
                WindowDragArea()
            }
            .frame(height: Theme.titlebarHeight)
            HLine()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    upNext
                    properties
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.bgSecondary)
    }

    // `tasks` changing re-renders this, so the MLFQ pick stays current.
    @ViewBuilder
    private var upNext: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Up next")
            if let next = try? model.store.nextTask() {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TagPill(categoryName: next.categoryName)
                        Spacer()
                        QueueBadge(level: QueueLevel(task: next))
                    }
                    Text(next.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textNormal)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        model.onNudgeNow()
                    } label: {
                        Label("Nudge now", systemImage: "bolt.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ObsidianButtonStyle(prominent: true))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bgPrimary))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                .onTapGesture { model.selectedTaskID = next.id }
            } else {
                Placeholder("Queue is empty. Press ⌥Space to capture something.")
            }
        }
    }

    @ViewBuilder
    private var properties: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("Properties")
            if let task = selectedTask {
                PropertyRow(symbol: "tag", key: "category") {
                    Menu(task.categoryName) {
                        ForEach(TaskCategory.defaults, id: \.self) { name in
                            Button(name) { model.perform { try $0.setCategory(task, to: name) } }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                PropertyRow(symbol: "square.stack.3d.up", key: "queue") {
                    Menu {
                        ForEach(QueueLevel.allCases, id: \.self) { level in
                            Button(level.title) { model.perform { try $0.setQueueLevel(task, to: level) } }
                        }
                    } label: {
                        QueueBadge(level: QueueLevel(task: task))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                PropertyRow(symbol: "arrow.uturn.right", key: "skips") {
                    SkipMeter(task: task)
                }
                PropertyRow(symbol: "calendar", key: "created") {
                    Text(task.createdAt, format: .dateTime.month().day().hour().minute())
                }
                PropertyRow(symbol: "checkmark.circle", key: "status") {
                    if let done = task.completedAt {
                        Text("Done \(done, format: .relative(presentation: .named))")
                    } else {
                        Text("Open")
                    }
                }
            } else {
                Placeholder("Select a task to see its properties.")
            }
        }
    }
}

private struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textMuted)
            .padding(.bottom, 2)
    }
}

private struct Placeholder: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.textFaint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PropertyRow<Value: View>: View {
    let symbol: String
    let key: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
                .frame(width: 14)
            Text(key)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 70, alignment: .leading)
            value
                .foregroundStyle(Theme.textNormal)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12.5))
        .padding(.vertical, 6)
    }
}

/// Progress toward the next MLFQ promotion.
private struct SkipMeter: View {
    let task: TaskItem

    var body: some View {
        if task.queueLevel == QueueLevel.high.rawValue {
            Text("\(task.skipCount) · top queue")
        } else {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(0..<MLFQ.promotionThreshold, id: \.self) { index in
                        Capsule()
                            .fill(index < task.skipCount ? Theme.accent : Theme.border)
                            .frame(width: 12, height: 5)
                    }
                }
                Text("\(task.skipCount)/\(MLFQ.promotionThreshold)")
                    .foregroundStyle(Theme.textMuted)
            }
            .help("Promotes one queue level after \(MLFQ.promotionThreshold) skips")
        }
    }
}
