import KarunManagerCore
import SwiftUI

/// The "editor": a tab bar plus the selected list rendered like a markdown note of `- [ ]` tasks.
struct TaskListPane: View {
    @Bindable var model: LibraryModel
    let tasks: [TaskItem]

    /// Folded subheadings, keyed per page so folding "Urgent" on one page doesn't fold it everywhere.
    @State private var collapsed: Set<String> = []
    /// Section currently under a dragged task.
    @State private var dropTargetID: String?

    private var sections: [TaskSection] {
        model.selection.sections(from: tasks, now: model.now)
    }

    private var visibleCount: Int {
        tasks.filter(model.selection.includes).count
    }

    /// Wherever the page or a subheading already names the category, rows drop the redundant tag.
    private var rowsShowCategory: Bool {
        switch model.selection {
        case .allOpen, .completed: true
        case .queue, .category: false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(title: model.selection.title, symbol: model.selection.symbol)
            HLine()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if model.selection != .completed {
                        TaskComposer(model: model)
                            .padding(.bottom, 18)
                    }
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                    if sections.isEmpty {
                        Text(model.selection == .completed ? "Nothing completed yet." : "Nothing here yet.")
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

    private func sectionView(_ section: TaskSection) -> some View {
        let _ = model.revision  // snoozes change Up next without touching SwiftData
        let positions = queuePositions(of: tasks, now: model.now)
        let upNextID = try? model.store.nextTask()?.id
        let key = "\(model.selection.title)/\(section.id)"
        let isCollapsed = collapsed.contains(key)
        let content = VStack(alignment: .leading, spacing: 0) {
            SectionHeading(section: section, isCollapsed: isCollapsed) {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isCollapsed { collapsed.remove(key) } else { collapsed.insert(key) }
                }
            }
            if !isCollapsed {
                ForEach(section.tasks) { task in
                    TaskRow(
                        task: task,
                        position: positions[task.id],
                        isUpNext: task.id == upNextID,
                        showsCategory: rowsShowCategory,
                        isSelected: model.selectedTaskID == task.id,
                        onToggle: { model.toggleCompleted(task) },
                        onSelect: { model.selectedTaskID = task.id },
                        onSetQueue: { model.setQueue(task, to: $0) }
                    )
                    .draggable(task.id.uuidString) { DragPreview(task: task) }
                    .contextMenu { contextMenu(for: task) }
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
                        if targeted {
                            dropTargetID = section.id
                        } else if dropTargetID == section.id {
                            dropTargetID = nil
                        }
                    }
            } else {
                content
            }
        }
    }

    /// Dropping on a priority section re-queues the task; on a category section, re-categorises it.
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.selection.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.textNormal)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textFaint)
            if case .category(let name) = model.selection {
                SkipDirectionControl(model: model, categoryName: name)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 22)
    }

    private var subtitle: String {
        let count = visibleCount
        switch model.selection {
        case .completed: return "\(count) done"
        case .queue: return "\(count) open · in nudge order · drag to re-categorise"
        default: return "\(count) open · in nudge order · drag to change priority"
        }
    }

    @ViewBuilder
    private func contextMenu(for task: TaskItem) -> some View {
        Menu("Move to queue") {
            ForEach(QueueLevel.allCases, id: \.self) { level in
                Button("\(level.title)  ⌘\(level.rawValue + 1)") { model.setQueue(task, to: level) }
                    .disabled(task.queueLevel == level.rawValue)
            }
        }
        Menu("Category") {
            ForEach(TaskCategory.defaults, id: \.self) { name in
                Button(name) { model.setCategory(task, to: name) }
                    .disabled(task.categoryName == name)
            }
        }
        Menu("Repeat") {
            RepeatRuleMenuItems(current: task.repeatRule) { model.setRepeatRule(task, to: $0) }
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
    /// Place in line within its queue; nil for completed or not-yet-available tasks.
    let position: Int?
    let isUpNext: Bool
    let showsCategory: Bool
    let isSelected: Bool
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
            Checkbox(isChecked: task.isCompleted, action: onToggle)
            Text(task.title)
                .font(.system(size: 15))
                .foregroundStyle(task.isCompleted ? Theme.textFaint : Theme.textNormal)
                .strikethrough(task.isCompleted, color: Theme.textFaint)
                .lineLimit(1)
            if showsCategory {
                TagPill(categoryName: task.categoryName)
            }
            Spacer(minLength: 12)
            RepeatLabel(task: task)
            if !task.isCompleted {
                if task.skipCount > 0 {
                    Label("\(task.skipCount)", systemImage: "arrow.uturn.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                        .help("Skipped \(task.skipCount) of \(MLFQ.promotionThreshold) before promotion")
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
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
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
            Text(current.explanation)
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
