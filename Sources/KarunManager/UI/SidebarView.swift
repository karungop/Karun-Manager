import KarunManagerCore
import SwiftUI

/// The "file explorer": queues and categories as folders, with live counts.
struct SidebarView: View {
    @Bindable var model: LibraryModel
    let tasks: [TaskItem]
    let index: LibraryIndex

    @State private var queuesExpanded = true
    @State private var categoriesExpanded = true
    @State private var dropTarget: SidebarItem?
    @State private var isAddingCategory = false
    @State private var renamingCategory: String?
    @State private var deletingCategory: String?

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

                    FolderHeader(title: "Categories", isExpanded: $categoriesExpanded) {
                        IconButton(symbol: "plus", help: "New category") { isAddingCategory = true }
                            .scaleEffect(0.8)
                            .popover(isPresented: $isAddingCategory, arrowEdge: .trailing) {
                                CategoryNamePopover(title: "New category", initial: "", action: "Add") { name in
                                    model.addCategory(name)
                                }
                            }
                    }
                    if categoriesExpanded {
                        ForEach(model.categories, id: \.self) { name in
                            row(.category(name), indent: true)
                                .contextMenu {
                                    Button("Rename…") { renamingCategory = name }
                                    Button("Delete…", role: .destructive) { deletingCategory = name }
                                        .disabled(model.categories.count <= 1)
                                }
                                .popover(isPresented: Binding(
                                    get: { renamingCategory == name },
                                    set: { if !$0 { renamingCategory = nil } }
                                ), arrowEdge: .trailing) {
                                    CategoryNamePopover(title: "Rename category", initial: name, action: "Rename") { new in
                                        model.renameCategory(name, to: new)
                                    }
                                }
                        }
                    }

                    Spacer().frame(height: 6)
                    row(.upcoming)
                    row(.completed)
                }
                .padding(.horizontal, 8)
            }
        }
        .background(Theme.bgSecondary)
        .confirmationDialog(
            "Delete “\(deletingCategory ?? "")”?",
            isPresented: Binding(get: { deletingCategory != nil }, set: { if !$0 { deletingCategory = nil } }),
            presenting: deletingCategory
        ) { name in
            Button("Delete category", role: .destructive) { model.deleteCategory(name) }
        } message: { name in
            let fallback = model.categories.first { $0 != name } ?? ""
            Text("Its tasks (open and completed) move to “\(fallback)”.")
        }
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
            count: index.counts[item] ?? 0,
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
            case .allOpen, .upcoming, .completed: break
            }
        }
        return true
    }
}

private extension SidebarItem {
    var acceptsDrops: Bool {
        switch self {
        case .queue, .category: true
        case .allOpen, .upcoming, .completed: false
        }
    }
}

private struct FolderHeader<Accessory: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 0) {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            accessory
        }
        .padding(.top, 8)
    }
}

extension FolderHeader where Accessory == EmptyView {
    init(title: String, isExpanded: Binding<Bool>) {
        self.init(title: title, isExpanded: isExpanded) { EmptyView() }
    }
}

/// Small popover with a name field, for adding or renaming a category.
private struct CategoryNamePopover: View {
    let title: String
    let initial: String
    let action: String
    /// Returns false if the name was rejected (blank or already taken).
    let onCommit: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var rejected = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textNormal)
            TextField("", text: $name, prompt: Text("Name").foregroundStyle(Theme.textFaint))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textNormal)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.2)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(rejected ? Theme.red : Theme.border))
                .focused($isFocused)
                .onSubmit(commit)
            if rejected {
                Text("That name is empty or already used.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(ObsidianButtonStyle())
                Button(action, action: commit)
                    .buttonStyle(ObsidianButtonStyle(prominent: true))
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(Theme.bgSecondary)
        .environment(\.colorScheme, .dark)
        .onAppear {
            name = initial
            isFocused = true
        }
    }

    private func commit() {
        if name == initial || onCommit(name) {
            dismiss()
        } else {
            rejected = true
        }
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
