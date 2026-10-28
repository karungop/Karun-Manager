import KarunManagerCore
import SwiftUI

/// The "editor": a tab bar plus the selected list rendered like a markdown note of `- [ ]` tasks.
struct TaskListPane: View {
    @Bindable var model: LibraryModel
    let tasks: [TaskItem]

    @State private var draft = ""

    private var visibleTasks: [TaskItem] {
        let filtered = tasks.filter(model.selection.includes)
        guard model.selection == .completed else { return filtered }
        return filtered.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(title: model.selection.title, symbol: model.selection.symbol)
            HLine()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(visibleTasks) { task in
                        TaskRow(
                            task: task,
                            isSelected: model.selectedTaskID == task.id,
                            onToggle: { model.toggleCompleted(task) },
                            onSelect: { model.selectedTaskID = task.id }
                        )
                        .contextMenu { contextMenu(for: task) }
                    }
                    if model.selection != .completed {
                        NewTaskLine(text: $draft) {
                            model.addTask(from: draft)
                            draft = ""
                        }
                    } else if visibleTasks.isEmpty {
                        Text("Nothing completed yet.")
                            .foregroundStyle(Theme.textFaint)
                            .padding(.horizontal, 10)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.top, 36)
                .padding(.bottom, 60)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.bgPrimary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.selection.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.textNormal)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 22)
    }

    private var subtitle: String {
        let count = visibleTasks.count
        if model.selection == .completed { return "\(count) done" }
        return "\(count) open · ordered by queue, then age"
    }

    @ViewBuilder
    private func contextMenu(for task: TaskItem) -> some View {
        Menu("Move to queue") {
            ForEach(QueueLevel.allCases, id: \.self) { level in
                Button(level.title) { model.perform { try $0.setQueueLevel(task, to: level) } }
                    .disabled(task.queueLevel == level.rawValue)
            }
        }
        Menu("Category") {
            ForEach(TaskCategory.defaults, id: \.self) { name in
                Button(name) { model.perform { try $0.setCategory(task, to: name) } }
                    .disabled(task.categoryName == name)
            }
        }
        Divider()
        Button(task.isCompleted ? "Mark open" : "Mark done") { model.toggleCompleted(task) }
        Button("Delete", role: .destructive) { model.delete(task) }
    }
}

private struct TabStrip: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(title).lineLimit(1)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.textNormal)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .frame(minWidth: 140, alignment: .leading)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7)
                    .fill(Theme.bgPrimary)
            )
            .padding(.leading, 10)
            WindowDragArea()
        }
        .frame(height: Theme.titlebarHeight, alignment: .bottom)
        .background(Theme.bgSecondary)
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let isSelected: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Checkbox(isChecked: task.isCompleted, action: onToggle)
            Text(task.title)
                .font(.system(size: 15))
                .foregroundStyle(task.isCompleted ? Theme.textFaint : Theme.textNormal)
                .strikethrough(task.isCompleted, color: Theme.textFaint)
                .lineLimit(1)
            TagPill(categoryName: task.categoryName)
            Spacer(minLength: 12)
            if !task.isCompleted {
                if task.skipCount > 0 {
                    Label("\(task.skipCount)", systemImage: "arrow.uturn.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                        .help("Skipped \(task.skipCount) of \(MLFQ.promotionThreshold) before promotion")
                }
                QueueBadge(level: QueueLevel(task: task))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Theme.selected : hovering ? Theme.hover : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
    }
}

private struct NewTaskLine: View {
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
                .frame(width: 16)
            TextField(
                "",
                text: $text,
                prompt: Text("New task — try buy: or call:").foregroundStyle(Theme.textFaint)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(Theme.textNormal)
            .onSubmit(onSubmit)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
