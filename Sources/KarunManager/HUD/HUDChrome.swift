import SwiftUI

/// Shared Obsidian-modal look for both HUDs.
struct HUDChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: 580)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.bgSecondary))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func hudChrome() -> some View { modifier(HUDChrome()) }
}

struct HUDCloseButton: View {
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(hovering ? Theme.textNormal : Theme.textFaint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(hovering ? Theme.hover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
