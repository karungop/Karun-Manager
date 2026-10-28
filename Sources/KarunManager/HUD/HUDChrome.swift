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
