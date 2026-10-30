import KarunManagerCore
import SwiftUI

/// The "editor": a tab bar plus the selected list rendered like a markdown note of `- [ ]` tasks.
struct TaskListPane: View {
    @Bindable var model: LibraryModel
    let tasks: [TaskItem]
    let index: LibraryIndex

    /// Folded subheadings, keyed per page so folding "Urgent" on one page doesn't fold it everywhere.
    @State private var collapsed: Set<String> = []
    /// Section or row currently under a dragged task.
    @State private var dropTargetID: String?
    @FocusState private var isListFocused: Bool

    private var sections: [TaskSection] {
        model.selection.sections(from: tasks, now: index.now, categories: model.categories, search: model.searchText)
    }

    /// Wherever the page or a subheading already names the category, rows drop the redundant tag.
    private var rowsShowCategory: Bool {
        switch model.selection {
        case .allOpen, .upcoming, .completed: true
        case .queue, .category: false
        }
    }

    var body: some View {
        let sections = self.sections
        VStack(spacing: 0) {
            TabStrip(model: model, title: model.selection.title, symbol: model.selection.symbol)
            HLine()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(sections)
                    if model.selection.acceptsNewTasks {
                        TaskComposer(model: model)
                            .padding(.bottom, 18)
                    }
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                    if sections.isEmpty {
                        Text(emptyMessage)
                            .foregroundStyle(Theme.textFaint)
                            .padding(.horizontal, 10)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.top, 36)
                .padding(.bottom, 80)
                .frame(maxWidth: .infinity)
            }
            // Keyboard navigation: ↑/↓ select, Space toggles done, ⌫ deletes, Return renames.
            .focusable()
            .focusEffectDisabled()
            .focused($isListFocused)
            .onKeyPress(.upArrow) { moveSelection(by: -1, in: sections) }
            .onKeyPress(.downArrow) { moveSelection(by: 1, in: sections) }
            .onKeyPress(.space) { actOnSelection { model.toggleCompleted($0) } }
            // ⌫ arrives as the "delete" command on macOS, not as a KeyPress for `.delete`.
            .onDeleteCommand { _ = actOnSelection { model.delete($0) } }
            .onKeyPress(.deleteForward) { actOnSelection { model.delete($0) } }
            .onKeyPress(.return) { actOnSelection { _ in model.editSelectedTitle() } }
        }
        .background(Theme.bgPrimary)
        .overlay(alignment: .bottom) {
            UndoBannerView(model: model).padding(.bottom, 34)
        }
    }

    private var emptyMessage: String {
        if !model.searchText.isEmpty { return "No tasks match “\(model.searchText)”." }
        switch model.selection {
        case .completed: return "Nothing completed yet."
        case .upcoming: return "No repeats scheduled. Completing a repeating task puts its next one here until its day."
        default: return "Nothing here yet."
        }
    }

    // MARK: Keyboard

    private func orderedVisibleTasks(_ sections: [TaskSection]) -> [TaskItem] {
        sections
            .filter { !collapsed.contains(collapseKey($0)) }
            .flatMap(\.tasks)
    }

    private func moveSelection(by step: Int, in sections: [TaskSection]) -> KeyPress.Result {
        let ordered = orderedVisibleTasks(sections)
        guard !ordered.isEmpty else { return .ignored }
        let current = ordered.firstIndex { $0.id == model.selectedTaskID }
        let next = current.map { min(max($0 + step, 0), ordered.count - 1) } ?? (step > 0 ? 0 : ordered.count - 1)
        model.selectedTaskID = ordered[next].id
        return .handled
    }

    private func actOnSelection(_ action: (TaskItem) -> Void) -> KeyPress.Result {
        guard let id = model.selectedTaskID, let task = tasks.first(where: { $0.id == id }) else { return .ignored }
        action(task)
        return .handled
    }

    // MARK: Sections

    private func collapseKey(_ section: TaskSection) -> String {
        "\(model.selection.title)/\(section.id)"
    }

    private func sectionView(_ section: TaskSection) -> some View {
        let key = collapseKey(section)
        let isCollapsed = collapsed.contains(key)
        let content = VStack(alignment: .leading, spacing: 0) {
            SectionHeading(section: section, isCollapsed: isCollapsed) {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isCollapsed { collapsed.remove(key) } else { collapsed.insert(key) }
                }
            }
            if !isCollapsed {
                ForEach(section.tasks) { task in
                    row(task, in: section)
                }
                if section.tasks.isEmpty && section.isDropTarget {
                    Text("No tasks — drag one here")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.leading, 36)
                        .padding(.vertical, 6)
                }
            }
        }
        .padding(.bottom, 4)
        .dropHighlight(dropTargetID == section.id)

        return Group {
            if section.isDropTarget {
                content
                    .dropDestination(for: String.self) { items, _ in
                        drop(items, on: section)
                    } isTargeted: { targeted in
                        setDropTarget(section.id, targeted)
                    }
            } else {
                content
            }
        }
    }

    private func row(_ task: TaskItem, in section: TaskSection) -> some View {
        let rowDropID = "row-\(task.id)"
        return TaskRow(
            task: task,
            now: index.now,
            position: index.positions[task.id],
            isUpNext: task.id == index.upNext?.id,
            showsCategory: rowsShowCategory,
            isSelected: model.selectedTaskID == task.id,
            skipThreshold: model.skipThreshold,
            isDropTarget: dropTargetID == rowDropID,
            onToggle: { model.toggleCompleted(task) },
            onSelect: {
                model.selectedTaskID = task.id
                isListFocused = true
            },
            onSetQueue: { model.setQueue(task, to: $0) }
        )
        .draggable(task.id.uuidString) { DragPreview(task: task) }
        .contextMenu { contextMenu(for: task) }
        // Dropping onto a row (rather than the section) puts the task right in front of it.
        .dropDestination(for: String.self) { items, _ in
            reorder(items, before: task)
        } isTargeted: { targeted in
            guard !task.isCompleted, task.isAvailable(at: index.now) else { return }
            setDropTarget(rowDropID, targeted)
        }
    }

    private func setDropTarget(_ id: String, _ targeted: Bool) {
        if targeted {
            dropTargetID = id
        } else if dropTargetID == id {
            dropTargetID = nil
        }
    }

    /// Dropping on a priority section sends the task to the back of that queue; on a category section,
    /// re-categorises it.
    private func drop(_ dragIDs: [String], on section: TaskSection) -> Bool {
        let dropped = dragIDs.compactMap { model.task(withDragID: $0, in: tasks) }
        guard !dropped.isEmpty else { return false }
        for task in dropped {
            switch section.marker {
            case .queue(let level): model.setQueue(task, to: level)
            case .category(let name): model.setCategory(task, to: name)
            case .upcoming, .none: return false
            }
        }
        return true
    }

    private func reorder(_ dragIDs: [String], before target: TaskItem) -> Bool {
        guard !target.isCompleted, target.isAvailable(at: index.now),
              let dragged = dragIDs.compactMap({ model.task(withDragID: $0, in: tasks) }).first,
              !dragged.isCompleted else { return false }
        if case .queue = model.selection, dragged.categoryName != target.categoryName {
            model.setCategory(dragged, to: target.categoryName)
        }
        model.move(dragged, before: target)
        return true
    }

    // MARK: Header

    private func header(_ sections: [TaskSection]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.selection.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.textNormal)
            HStack(spacing: 10) {
                Text(subtitle(count: sections.reduce(0) { $0 + $1.tasks.count }))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textFaint)
                if model.selection == .completed && !sections.isEmpty {
                    Spacer()
                    Button("Clear completed") { model.clearCompleted() }
                        .buttonStyle(ObsidianButtonStyle())
                        .help("Removes every completed task (you can undo)")
                }
            }
            if case .category(let name) = model.selection {
                SkipDirectionControl(model: model, categoryName: name)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 22)
    }

    private func subtitle(count: Int) -> String {
        let filtered = model.searchText.isEmpty ? "" : " matching “\(model.searchText)”"
        switch model.selection {
        case .completed: return "\(count) done\(filtered)"
        case .upcoming: return "\(count) scheduled\(filtered) · each moves into the queues on its day"
        case .queue: return "\(count) open\(filtered) · in nudge order · drag to reorder or re-categorise"
        default: return "\(count) open\(filtered) · in nudge order · drag to reorder or change priority"
        }
    }

    @ViewBuilder
    private func contextMenu(for task: TaskItem) -> some View {
        Button("Rename") {
            model.selectedTaskID = task.id
            model.editSelectedTitle()
        }
        Menu("Move to queue") {
            ForEach(QueueLevel.allCases, id: \.self) { level in
                Button("\(level.title)  ⌘\(level.rawValue + 1)") { model.setQueue(task, to: level) }
                    .disabled(task.queueLevel == level.rawValue)
            }
        }
        Menu("Category") {
            ForEach(model.categories, id: \.self) { name in
                Button(name) { model.setCategory(task, to: name) }
                    .disabled(task.categoryName == name)
            }
        }
        Menu("Repeat") {
            RepeatRuleMenuItems(current: task.repeatRule) { model.setRepeatRule(task, to: $0) }
        }
        let isUpcoming = !task.isCompleted && !task.isAvailable(at: index.now)
        if isUpcoming {
            Button("Make available now") { model.makeAvailableNow(task) }
        } else if task.isSnoozed(at: index.now) {
            Button("Wake from snooze") { model.unsnooze(task) }
        } else if !task.isCompleted {
            Button("Snooze 1 hour") { model.snooze(task) }
        }
        Divider()
        if !isUpcoming {
            Button(task.isCompleted ? "Mark open" : "Mark done") { model.toggleCompleted(task) }
        }
        Button(isUpcoming ? "Delete (ends the repeat)" : "Delete", role: .destructive) { model.delete(task) }
    }
}

private struct TabStrip: View {
    @Bindable var model: LibraryModel
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
            SearchField(model: model)
                .frame(width: 220)
                .padding(.trailing, 12)
                .frame(height: Theme.titlebarHeight)
        }
        .frame(height: Theme.titlebarHeight, alignment: .bottom)
        .background(Theme.bgSecondary)
    }
}

private struct SearchField: View {
    @Bindable var model: LibraryModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
            TextField("", text: $model.searchText, prompt: Text("Search").foregroundStyle(Theme.textFaint))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textNormal)
                .focused($isFocused)
                .onExitCommand {
                    model.searchText = ""
                    isFocused = false
                }
            if model.searchText.isEmpty {
                KbdChip(keys: "⌘F")
            } else {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.2)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isFocused ? Theme.accent.opacity(0.6) : Theme.border))
        .onChange(of: model.searchFocusRequest) { isFocused = true }
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let now: Date
    /// Place in line within its queue; nil for completed or not-yet-available tasks.
    let position: Int?
    let isUpNext: Bool
    let showsCategory: Bool
    let isSelected: Bool
    let skipThreshold: Int
    /// A dragged task will land just above this row.
    let isDropTarget: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void
    let onSetQueue: (QueueLevel) -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(position.map { "\($0)" } ?? "")
                .font(.system(size: 11, weight: isUpNext ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isUpNext ? Theme.accent : Theme.textFaint.opacity(0.8))
                .frame(width: 16, alignment: .trailing)
                .help(isUpNext ? "Up next — the next nudge shows this" : "Place in its queue's line")
            if !task.isCompleted && !task.isAvailable(at: now) {
                // Upcoming: can't be checked off until its day.
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textFaint)
                    .frame(width: 16, height: 16)
                    .help("Comes back on its day — use “Make available now” to do it early")
            } else {
                Checkbox(isChecked: task.isCompleted, action: onToggle)
            }
            Text(task.title)
                .font(.system(size: 15))
                .foregroundStyle(task.isCompleted || task.isSnoozed(at: now) ? Theme.textFaint : Theme.textNormal)
                .strikethrough(task.isCompleted, color: Theme.textFaint)
                .lineLimit(1)
            if task.notes != nil {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textFaint)
                    .help("Has notes")
            }
            if showsCategory {
                TagPill(categoryName: task.categoryName)
            }
            Spacer(minLength: 12)
            if !task.isCompleted {
                SnoozeLabel(task: task, now: now)
                DueLabel(task: task, now: now)
            }
            RepeatLabel(task: task)
            if !task.isCompleted {
                if task.skipCount > 0 {
                    Label("\(task.skipCount)", systemImage: "arrow.uturn.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                        .help("Skipped \(task.skipCount) of \(skipThreshold) before it changes queue")
                }
                QueueMenu(task: task, onSelect: onSetQueue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Theme.selected : hovering ? Theme.hover : .clear)
        )
        .overlay(alignment: .top) {
            if isDropTarget {
                Capsule().fill(Theme.accent).frame(height: 2).offset(y: -1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
    }
}

/// "Due today", "Due Fri", red "Overdue · Oct 27".
private struct DueLabel: View {
    let task: TaskItem
    let now: Date

    var body: some View {
        if let due = task.dueDate {
            let calendar = Calendar.current
            let overdue = calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
            HStack(spacing: 4) {
                Image(systemName: overdue ? "exclamationmark.circle" : "calendar")
                Text(DueLabel.text(for: due, now: now, overdue: overdue))
            }
            .font(.system(size: 11, weight: overdue ? .semibold : .regular))
            .foregroundStyle(overdue ? Theme.red : calendar.isDate(due, inSameDayAs: now) ? Theme.orange : Theme.textFaint)
            .lineLimit(1)
            .fixedSize()
        }
    }

    static func text(for due: Date, now: Date, overdue: Bool) -> String {
        let calendar = Calendar.current
        let day = due.formatted(.dateTime.month(.abbreviated).day())
        if overdue { return "Overdue · \(day)" }
        if calendar.isDate(due, inSameDayAs: now) { return "Due today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
            return "Due tomorrow"
        }
        return "Due \(day)"
    }
}

/// "zz until 3:40 PM" while a task is snoozed.
private struct SnoozeLabel: View {
    let task: TaskItem
    let now: Date

    var body: some View {
        if let until = task.snoozedUntil, until > now {
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz")
                Text("until \(until, format: .dateTime.hour().minute())")
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.blue)
            .lineLimit(1)
            .fixedSize()
            .help("Snoozed — hidden from nudges until then")
        }
    }
}

/// "Deleted “X” · Undo ⌘Z", fading out after a few seconds.
private struct UndoBannerView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        if let banner = model.undoBanner {
            HStack(spacing: 12) {
                Text(banner.message)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textNormal)
                Button("Undo") { model.undo() }
                    .buttonStyle(ObsidianButtonStyle(prominent: true))
                KbdChip(keys: "⌘Z")
            }
            .font(.system(size: 12.5))
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.bgSecondary))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: banner.id) {
                try? await Task.sleep(for: .seconds(6))
                if model.undoBanner?.id == banner.id {
                    withAnimation { model.undoBanner = nil }
                }
            }
        }
    }
}

/// An Obsidian-style H3 with a fold chevron, like folding a heading in a note.
private struct SectionHeading: View {
    let section: TaskSection
    let isCollapsed: Bool
    let onToggle: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .foregroundStyle(Theme.textFaint)
                    .opacity(hovering || isCollapsed ? 1 : 0)
                    .frame(width: 10)
                marker
                Text(section.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textNormal)
                Text("\(section.tasks.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textFaint)
                Spacer()
            }
            .padding(.leading, -8)
            .padding(.horizontal, 10)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var marker: some View {
        switch section.marker {
        case .queue(let level):
            Circle().fill(level.color).frame(width: 8, height: 8)
        case .category(let name):
            Image(systemName: CategoryStyle.symbol(name))
                .font(.system(size: 12))
                .foregroundStyle(Theme.tagText)
        case .upcoming:
            Image(systemName: "calendar")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
        case .none:
            EmptyView()
        }
    }
}

/// "On skip: ↑ Promote | ↓ Demote" for the category whose page is open.
struct SkipDirectionControl: View {
    let model: LibraryModel
    let categoryName: String

    var body: some View {
        let current = model.skipDirection(for: categoryName)
        HStack(spacing: 10) {
            Text("When skipped")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textMuted)
            HStack(spacing: 2) {
                ForEach(SkipDirection.allCases, id: \.self) { direction in
                    let isSelected = direction == current
                    Button {
                        model.setSkipDirection(direction, for: categoryName)
                    } label: {
                        Label(direction.title, systemImage: direction.symbol)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(isSelected ? Theme.textNormal : Theme.textMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? Theme.selected : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
            Text(current.explanation(threshold: model.skipThreshold))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textFaint)
                .lineLimit(1)
        }
    }
}

/// "↻ Weekly", plus when a scheduled repeat becomes available ("↻ Weekly · in 6 days").
private struct RepeatLabel: View {
    let task: TaskItem

    var body: some View {
        if task.repeatRule != .never {
            HStack(spacing: 4) {
                Image(systemName: "repeat")
                Text(task.repeatRule.title)
                if !task.isCompleted, let date = task.availableFrom, date > Date() {
                    Text("· \(date, format: .relative(presentation: .named))")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.textFaint)
            .lineLimit(1)
            .fixedSize()
        }
    }
}

private struct DragPreview: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(QueueLevel(task: task).color).frame(width: 7, height: 7)
            Text(task.title).lineLimit(1)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.textNormal)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.bgSecondary))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.accent.opacity(0.6)))
        .environment(\.colorScheme, .dark)
    }
}
