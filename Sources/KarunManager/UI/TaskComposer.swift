import KarunManagerCore
import SwiftUI

/// The in-window place to create tasks (the HUD is only for when the window isn't in front).
struct TaskComposer: View {
    @Bindable var model: LibraryModel

    @State private var text = ""
    @State private var category = TaskCategory.thingsToDo
    @State private var level = QueueLevel.medium
    @State private var repeatRule = RepeatRule.never
    @FocusState private var isFocused: Bool

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isFocused ? Theme.accent : Theme.textFaint)
                TextField(
                    "",
                    text: $text,
                    prompt: Text("Add a task…").foregroundStyle(Theme.textFaint)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textNormal)
                .focused($isFocused)
                .onSubmit(submit)
                .onExitCommand { isFocused = false }
                if !isFocused { KbdChip(keys: "⌘N") }
            }

            // Stacks onto two lines when the pane is too narrow for one.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    CategoryMenu(selection: $category)
                    RepeatMenu(selection: $repeatRule)
                    Spacer(minLength: 12)
                    QueuePicker(selection: level) { level = $0 }
                    addButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    QueuePicker(selection: level) { level = $0 }
                    HStack {
                        CategoryMenu(selection: $category)
                        RepeatMenu(selection: $repeatRule)
                        Spacer()
                        addButton
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bgSecondary))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isFocused ? Theme.accent.opacity(0.7) : Theme.border)
        )
        .onChange(of: model.composerFocusRequest) { isFocused = true }
        .onChange(of: model.selection, initial: true) { applyDefaults(from: model.selection) }
    }

    private var addButton: some View {
        Button("Add", action: submit)
            .buttonStyle(ObsidianButtonStyle(prominent: true))
            .fixedSize()
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.45)
    }

    private func submit() {
        guard model.addTask(text: text, categoryName: category, level: level, repeatRule: repeatRule) else { return }
        text = ""
        repeatRule = .never
        isFocused = true  // keep going: rapid entry
    }

    /// New tasks inherit whichever queue or category is open in the sidebar.
    private func applyDefaults(from selection: SidebarItem) {
        switch selection {
        case .queue(let selected): level = selected
        case .category(let selected): category = selected
        default: break
        }
    }
}

/// The category as a tag chip that opens a menu of categories.
private struct CategoryMenu: View {
    @Binding var selection: String

    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(TaskCategory.defaults, id: \.self) { name in
                Button {
                    selection = name
                } label: {
                    if name == selection {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(CategoryStyle.tag(selection)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .fixedSize()
            .font(.system(size: 12))
            .foregroundStyle(Theme.tagText)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.tagBackground.opacity(hovering ? 1.6 : 1)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Category — or type buy: / call: / todo: before the task")
    }
}

/// "↻" chip; shows the rule's name once one is chosen.
private struct RepeatMenu: View {
    @Binding var selection: RepeatRule

    @State private var hovering = false

    var body: some View {
        let isSet = selection != .never
        Menu {
            RepeatRuleMenuItems(current: selection) { selection = $0 }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "repeat").font(.system(size: 10.5, weight: .semibold))
                if isSet { Text(selection.title).lineLimit(1) }
            }
            .fixedSize()
            .font(.system(size: 12))
            .foregroundStyle(isSet ? Theme.textNormal : Theme.textMuted)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(isSet || hovering ? 0.09 : 0.04)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Repeat: \(selection.title)")
    }
}
