import SwiftUI

struct QuickCaptureView: View {
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
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
                .onSubmit { onSubmit(text) }
                .onExitCommand(perform: onCancel)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)

            HLine()

            HStack(spacing: 14) {
                Text("Prefix with").foregroundStyle(Theme.textFaint)
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
        .onAppear { isFocused = true }
    }
}
