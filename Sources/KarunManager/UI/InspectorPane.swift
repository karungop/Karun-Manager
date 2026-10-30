import KarunManagerCore
import SwiftUI

/// Right sidebar: what the next nudge will show, plus Obsidian-style "Properties" for the selected task.
struct InspectorPane: View {
    @Bindable var model: LibraryModel
    let tasks: [TaskItem]
    let index: LibraryIndex

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

    @ViewBuilder
    private var upNext: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Up next")
            if let next = index.upNext {
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
                            .help("Sends it to the back of its queue and counts toward moving it")
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
                TitleEditor(model: model, task: task)
                    .id(task.id)
                    .padding(.bottom, 8)
                PropertyRow(symbol: "tag", key: "category") {
                    Menu(task.categoryName) {
                        ForEach(model.categories, id: \.self) { name in
                            Button(name) { model.setCategory(task, to: name) }
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
                DueDateRow(model: model, task: task)
                if !task.isCompleted {
                    SnoozeRow(model: model, task: task, now: index.now)
                }
                let direction = model.skipDirection(for: task.categoryName)
                PropertyRow(symbol: "arrow.uturn.right", key: "skips") {
                    SkipMeter(task: task, direction: direction, threshold: model.skipThreshold)
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
                    .help("Applies to every task in \(task.categoryName). \(direction.explanation(threshold: model.skipThreshold))")
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
                if !task.isCompleted, let next = task.availableFrom, next > index.now {
                    PropertyRow(symbol: "calendar.badge.clock", key: "comes back") {
                        Text(next, format: .dateTime.weekday(.abbreviated).month().day())
                        Button("Now") { model.makeAvailableNow(task) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.tagText)
                            .help("Move it into the open queues today")
                    }
                }
                PropertyRow(symbol: "clock", key: "created") {
                    Text(task.createdAt, format: .dateTime.month().day().hour().minute())
                }
                PropertyRow(symbol: "checkmark.circle", key: "status") {
                    if let done = task.completedAt {
                        Text("Done \(done, format: .relative(presentation: .named))")
                    } else {
                        Text("Open")
                    }
                }
                NotesEditor(model: model, task: task)
                    .id(task.id)
                    .padding(.top, 12)
            } else {
                Placeholder("Select a task to see its properties.")
            }
        }
    }
}

/// Click-to-edit title. Saves on Return or when focus leaves; Esc reverts.
private struct TitleEditor: View {
    @Bindable var model: LibraryModel
    let task: TaskItem

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $draft, prompt: Text("Task title").foregroundStyle(Theme.textFaint), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.textNormal)
            .lineLimit(1...4)
            .fixedSize(horizontal: false, vertical: true)
            .focused($isFocused)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(isFocused ? Color.black.opacity(0.2) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isFocused ? Theme.accent.opacity(0.6) : .clear))
            .padding(.horizontal, -6)
            .onAppear { draft = task.title }
            .onChange(of: task.title) { if !isFocused { draft = task.title } }
            .onSubmit(commit)
            .onExitCommand {
                draft = task.title
                isFocused = false
            }
            .onChange(of: isFocused) { if !isFocused { commit() } }
            .onChange(of: model.titleEditRequest) { isFocused = true }
            .help("Click to rename (or press Return on a selected task)")
    }

    private func commit() {
        guard draft != task.title else { return }
        model.setTitle(task, to: draft)
        draft = task.title  // blank input is rejected; show the real title again
        isFocused = false
    }
}

/// Obsidian-style note body under the properties. Saves when focus leaves.
private struct NotesEditor: View {
    @Bindable var model: LibraryModel
    let task: TaskItem

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Notes")
            TextField("", text: $draft, prompt: Text("Add notes…").foregroundStyle(Theme.textFaint), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textNormal)
                .lineLimit(3...12)
                .focused($isFocused)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bgPrimary))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isFocused ? Theme.accent.opacity(0.6) : Theme.border))
                .onAppear { draft = task.notes ?? "" }
                .onChange(of: isFocused) { if !isFocused { model.setNotes(task, to: draft) } }
        }
    }
}

private struct DueDateRow: View {
    @Bindable var model: LibraryModel
    let task: TaskItem

    var body: some View {
        PropertyRow(symbol: "calendar", key: "due") {
            if let due = task.dueDate {
                DatePicker(
                    "",
                    selection: Binding(get: { due }, set: { model.setDueDate(task, to: $0) }),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .fixedSize()
                Button {
                    model.setDueDate(task, to: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textFaint)
                .help("Remove due date")
            } else {
                Menu("Add…") {
                    Button("Today") { setDue(daysFromNow: 0) }
                    Button("Tomorrow") { setDue(daysFromNow: 1) }
                    Button("In a week") { setDue(daysFromNow: 7) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundStyle(Theme.textFaint)
            }
        }
    }

    private func setDue(daysFromNow days: Int) {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: Date()))
        model.setDueDate(task, to: day)
    }
}

private struct SnoozeRow: View {
    @Bindable var model: LibraryModel
    let task: TaskItem
    let now: Date

    var body: some View {
        PropertyRow(symbol: "moon.zzz", key: "snooze") {
            if let until = task.snoozedUntil, until > now {
                Text("until \(until, format: .dateTime.hour().minute())")
                Button("Wake") { model.unsnooze(task) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.tagText)
            } else {
                Button("Snooze 1h") { model.snooze(task) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textFaint)
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
    let threshold: Int

    var body: some View {
        if let target = MLFQ.nextLevel(for: task, direction: direction) {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(0..<threshold, id: \.self) { index in
                        Capsule()
                            .fill(index < task.skipCount ? Theme.accent : Theme.border)
                            .frame(width: max(3, 56 / CGFloat(threshold)), height: 5)
                    }
                }
                Text("\(task.skipCount)/\(threshold)")
                    .foregroundStyle(Theme.textMuted)
                Image(systemName: direction.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(target.color)
            }
            .help("Moves to \(target.title) after \(threshold) skips")
        } else {
            Text(direction == .stay ? "\(task.skipCount) · stays in queue" : "\(task.skipCount) · bottom queue")
        }
    }
}
