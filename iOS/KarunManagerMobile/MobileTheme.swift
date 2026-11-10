import KarunManagerCore
import SwiftUI

/// The Mac app's dark palette (Sources/KarunManager/UI/Theme.swift), so both apps look like one product.
enum MobileTheme {
    static let bgPrimary = Color(hex: 0x1E1E1E)
    static let bgSecondary = Color(hex: 0x262626)
    static let border = Color(hex: 0x363636)

    static let textNormal = Color(hex: 0xDADADA)
    static let textMuted = Color(hex: 0xA3A3A3)
    static let textFaint = Color(hex: 0x666666)

    static let accent = Color(hex: 0x8A5CF5)
    static let tagText = Color(hex: 0xA88BFA)
    static let tagBackground = Color(hex: 0x8A5CF5).opacity(0.15)

    static let red = Color(hex: 0xFB464C)
    static let orange = Color(hex: 0xE9973F)
    static let blue = Color(hex: 0x53A6FF)
    static let green = Color(hex: 0x44CF6E)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension QueueLevel {
    var title: String {
        switch self {
        case .high: "Urgent"
        case .medium: "Standard"
        case .low: "Someday"
        }
    }

    var color: Color {
        switch self {
        case .high: MobileTheme.red
        case .medium: MobileTheme.orange
        case .low: MobileTheme.blue
        }
    }
}
