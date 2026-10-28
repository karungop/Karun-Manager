import KarunManagerCore
import SwiftUI

/// The "file explorer": queues and categories as folders, with live counts.
struct SidebarView: View {
    @Bindable var model: LibraryModel
    let tasks: [TaskItem]

    @State private var queuesExpanded = true
    @State private var categoriesExpanded = true
    @State private var dropTarget: SidebarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .trailing) {
                WindowDragArea()
                IconButton(symbol: "plus", help: "New task (⌘N)") { model.focusComposer() }
                    .padding(.trailing, 8)
            }
            .frame(height: Theme.titlebarHeight)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    Text("KARUN MANAGER")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.textFaint)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)

                    row(.allOpen)

                    FolderHeader(title: "Queues", isExpanded: $queuesExpanded)
                    if queuesExpanded {
                        ForEach(QueueLevel.allCases, id: \.self) { level in
                            row(.queue(level), indent: true) {
                                Circle().fill(level.color).frame(width: 7, height: 7)
                            }
                        }
                    }

                    FolderHeader(title: "Categories", isExpanded: $categoriesExpanded)
                    if categoriesExpanded {
                        ForEach(TaskCategory.defaults, id: \.self) { name in
                            row(.category(name), indent: true)
                        }
                    }

                    Spacer().frame(height: 6)
                    row(.completed)
                }
                .padding(.horizontal, 8)
            }
        }
        .background(Theme.bgSecondary)
    }

    private func row(_ item: SidebarItem, indent: Bool = false) -> some View {
        row(item, indent: indent) {
            Image(systemName: item.symbol)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private func row(_ item: SidebarItem, indent: Bool, @ViewBuilder icon: () -> some View) -> some View {
        SidebarRow(
            title: item.title,
            count: tasks.filter(item.includes).count,
            isSelected: model.selection == item,
            indent: indent,
            icon: icon()
        ) {
            model.selection = item
        }
        .dropHighlight(dropTarget == item)
        .dropDestination(for: String.self) { items, _ in
            drop(items, on: item)
        } isTargeted: { targeted in
            guard item.acceptsDrops else { return }
            if targeted {
                dropTarget = item
            } else if dropTarget == item {
                dropTarget = nil
            }
        }
    }

    /// Dropping a task on a queue folder re-queues it; on a category folder, re-categorises it.
    private func drop(_ dragIDs: [String], on item: SidebarItem) -> Bool {
        let dropped = dragIDs.compactMap { model.task(withDragID: $0, in: tasks) }
        guard item.acceptsDrops, !dropped.isEmpty else { return false }
        for task in dropped {
            switch item {
            case .queue(let level): model.setQueue(task, to: level)
            case .category(let name): model.setCategory(task, to: name)
            case .allOpen, .completed: break
            }
        }
        return true
    }
}

private extension SidebarItem {
    var acceptsDrops: Bool {
        switch self {
        case .queue, .category: true
        case .allOpen, .completed: false
        }
    }
}

private struct FolderHeader: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarRow<Icon: View>: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let indent: Bool
    let icon: Icon
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon.frame(width: 14)
                Text(title)
                    .foregroundStyle(isSelected ? Theme.textNormal : Theme.textMuted)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .font(.system(size: 13))
            .padding(.leading, indent ? 24 : 6)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Theme.selected : hovering ? Theme.hover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
