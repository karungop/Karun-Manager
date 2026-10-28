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

    // `tasks` changes re-render this; `revision` covers snoozes, which SwiftData doesn't see.
    @ViewBuilder
    private var upNext: some View {
        let _ = model.revision
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
                    // Same actions as the nudge HUD, handled in place while the window is up.
                    HStack(spacing: 6) {
                        Button("Done") { model.complete(next) }
                            .buttonStyle(ObsidianButtonStyle(prominent: true))
                        Button("Snooze 1h") { model.snooze(next) }
                            .buttonStyle(ObsidianButtonStyle())
                        Button("Skip") { model.skip(next) }
                            .buttonStyle(ObsidianButtonStyle())
                            .help("Counts toward promotion, like skipping a nudge")
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bgPrimary))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                .onTapGesture { model.selectedTaskID = next.id }
            } else {
                Placeholder("Queue is empty. Add something with ⌘N.")
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
                    Text("⌘1 – ⌘3").foregroundStyle(Theme.textFaint)
                }
                QueuePicker(selection: QueueLevel(task: task), fillsWidth: true) { model.setQueue(task, to: $0) }
                    .padding(.bottom, 4)
                let direction = model.skipDirection(for: task.categoryName)
                PropertyRow(symbol: "arrow.uturn.right", key: "skips") {
                    SkipMeter(task: task, direction: direction)
                }
                PropertyRow(symbol: direction.symbol, key: "on skip") {
                    Menu {
                        ForEach(SkipDirection.allCases, id: \.self) { option in
                            Button(option.title) { model.setSkipDirection(option, for: task.categoryName) }
                        }
                    } label: {
                        Text(direction.title)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Applies to every task in \(task.categoryName). \(direction.explanation)")
                }
                PropertyRow(symbol: "repeat", key: "repeat") {
                    Menu {
                        RepeatRuleMenuItems(current: task.repeatRule) { model.setRepeatRule(task, to: $0) }
                    } label: {
                        Text(task.repeatRule.title)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Completing a repeating task schedules the next one")
                }
                if !task.isCompleted, let next = task.availableFrom, next > model.now {
                    PropertyRow(symbol: "calendar.badge.clock", key: "available") {
                        Text(next, format: .dateTime.weekday(.abbreviated).month().day())
                    }
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

/// Progress toward the next skip-triggered move, in this category's direction.
private struct SkipMeter: View {
    let task: TaskItem
    let direction: SkipDirection

    var body: some View {
        if let target = MLFQ.nextLevel(for: task, direction: direction) {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(0..<MLFQ.promotionThreshold, id: \.self) { index in
                        Capsule()
                            .fill(index < task.skipCount ? Theme.accent : Theme.border)
                            .frame(width: 10, height: 5)
                    }
                }
                Text("\(task.skipCount)/\(MLFQ.promotionThreshold)")
                    .foregroundStyle(Theme.textMuted)
                Image(systemName: direction.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(target.color)
            }
            .help("Moves to \(target.title) after \(MLFQ.promotionThreshold) skips")
        } else {
            Text("\(task.skipCount) · \(direction == .promote ? "top" : "bottom") queue")
        }
    }
}
