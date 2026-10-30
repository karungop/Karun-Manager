import KarunManagerCore
import SwiftUI

/// Category and priority for a task captured from a HUD.
struct CaptureOptions: Equatable {
    var categoryName: String
    var level = QueueLevel.medium

    init(categories: [String]) {
        categoryName = categories.first ?? TaskCategory.thingsToDo
    }
}

/// Category dropdown + priority picker for HUD capture, with keyboard shortcuts since the HUDs
/// are keyboard-first: ⌘1–3 picks the priority, ⌃1–3 the category. (Not ⌥: Option-only keystrokes
/// never reach shortcuts on macOS — a focused text field types them as characters like "£".)
struct CaptureOptionsBar: View {
    let categories: [String]
    @Binding var options: CaptureOptions

    /// ⌃1–⌃9 cover the first nine categories.
    private var shortcutCategories: [String] { Array(categories.prefix(9)) }

    var body: some View {
        HStack(spacing: 8) {
            CategoryMenu(categories: categories, selection: $options.categoryName)
            KbdChip(keys: shortcutCategories.count > 1 ? "⌃1–\(shortcutCategories.count)" : "⌃1")
            Spacer(minLength: 10)
            KbdChip(keys: "⌘1–3")
            QueuePicker(selection: options.level) { options.level = $0 }
        }
        .background { shortcuts }
    }

    /// Invisible buttons that own the shortcuts while the HUD is key.
    private var shortcuts: some View {
        ZStack {
            ForEach(QueueLevel.allCases, id: \.self) { level in
                Button("") { options.level = level }
                    .keyboardShortcut(KeyEquivalent(Character("\(level.rawValue + 1)")), modifiers: .command)
            }
            ForEach(Array(shortcutCategories.enumerated()), id: \.offset) { index, name in
                Button("") { options.categoryName = name }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
