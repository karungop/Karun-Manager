import KarunManagerCore
import SwiftUI

/// Always-visible capture bar: type, pick a category and queue, press Return. Focus stays in the field so
/// several tasks can be added in a row. Prefixes such as "buy:" pick the category, as on the Mac.
struct ComposerBar: View {
    @Environment(MobileModel.self) private var model
    @State private var text = ""
    @State private var chosenCategory: String?
    @State private var queue: QueueLevel = .medium
    @FocusState private var focused: Bool

    /// The chosen category, or the first one if nothing was chosen or it was renamed or deleted on the Mac.
    private var category: String {
        chosenCategory.flatMap { model.categories.contains($0) ? $0 : nil }
            ?? model.categories.first
            ?? TaskCategory.thingsToDo
    }

    private var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Add a task…", text: $text)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(MobileTheme.bgPrimary, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(MobileTheme.border))
                Button(action: add) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(isBlank ? MobileTheme.textFaint : MobileTheme.accent)
                }
                .disabled(isBlank)
                .accessibilityLabel("Add task")
            }
            HStack {
                Menu {
                    Picker("Category", selection: Binding(get: { category }, set: { chosenCategory = $0 })) {
                        ForEach(model.categories, id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("#" + CaptureParser.slug(category))
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.tagText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(MobileTheme.tagBackground, in: Capsule())
                }
                Spacer()
                Picker("Queue", selection: $queue) {
                    ForEach(QueueLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(MobileTheme.bgSecondary)
        .overlay(alignment: .top) { Divider().overlay(MobileTheme.border) }
    }

    private func add() {
        guard model.add(text, category: category, queue: queue) else { return }
        text = ""
        focused = true
    }
}
