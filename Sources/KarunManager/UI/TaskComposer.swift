import KarunManagerCore
import SwiftUI

/// The in-window place to create tasks (the HUD is only for when the window isn't in front).
/// Category / priority / repeat live on `LibraryModel` so window shortcuts (⌘1–3) can set them.
struct TaskComposer: View {
    @Bindable var model: LibraryModel

    @State private var text = ""
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
                KbdChip(keys: isFocused ? "⌘1–3 priority" : "⌘N")
            }

            // Stacks onto two lines when the pane is too narrow for one.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    CategoryMenu(categories: model.categories, selection: $model.composerCategory)
                    RepeatMenu(selection: $model.composerRepeat)
                    Spacer(minLength: 12)
                    QueuePicker(selection: model.composerLevel) { model.composerLevel = $0 }
                    addButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    QueuePicker(selection: model.composerLevel) { model.composerLevel = $0 }
                    HStack {
                        CategoryMenu(categories: model.categories, selection: $model.composerCategory)
                        RepeatMenu(selection: $model.composerRepeat)
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
        .onChange(of: isFocused) { model.isComposerFocused = isFocused }
    }

    private var addButton: some View {
        Button("Add", action: submit)
            .buttonStyle(ObsidianButtonStyle(prominent: true))
            .fixedSize()
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.45)
    }

    private func submit() {
        guard model.submitComposer(text) else { return }
        text = ""
        isFocused = true  // keep going: rapid entry
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
