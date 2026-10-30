import SwiftUI

struct QuickCaptureView: View {
    let focus: HUDFocus
    let categories: [String]
    let onSubmit: (String, CaptureOptions) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @State private var options: CaptureOptions

    init(
        focus: HUDFocus,
        categories: [String],
        onSubmit: @escaping (String, CaptureOptions) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.focus = focus
        self.categories = categories
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _options = State(initialValue: CaptureOptions(categories: categories))
    }
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.accent)
                TextField(
                    "",
                    text: $text,
                    prompt: Text("What's on your mind?").foregroundStyle(Theme.textFaint)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .foregroundStyle(Theme.textNormal)
                .focused($isFocused)
                .onSubmit { onSubmit(text, options) }
                .onExitCommand(perform: onCancel)
                HUDCloseButton(help: "Dismiss (esc)", action: onCancel)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)

            CaptureOptionsBar(categories: categories, options: $options)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

            HLine()

            HStack(spacing: 14) {
                Text("Or prefix").foregroundStyle(Theme.textFaint)
                    + Text("  buy:  call:  todo:").foregroundStyle(Theme.tagText)
                Spacer()
                HStack(spacing: 5) { KbdChip(keys: "↩"); Text("save") }
                HStack(spacing: 5) { KbdChip(keys: "esc"); Text("dismiss") }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.textFaint)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .hudChrome()
        .onAppear { if focus.focusOnAppear { isFocused = true } }
        .onChange(of: focus.captureRequest) { isFocused = true }
    }
}
