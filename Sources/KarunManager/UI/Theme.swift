import AppKit
import KarunManagerCore
import SwiftUI

/// Obsidian's default dark theme, expressed as a small token set.
enum Theme {
    static let bgPrimary = Color(hex: 0x1E1E1E)    // editor
    static let bgSecondary = Color(hex: 0x262626)  // sidebars, tab bar, HUDs
    static let border = Color(hex: 0x363636)
    static let hover = Color.white.opacity(0.06)
    static let selected = Color.white.opacity(0.10)

    static let textNormal = Color(hex: 0xDADADA)
    static let textMuted = Color(hex: 0xA3A3A3)
    static let textFaint = Color(hex: 0x666666)

    static let accent = Color(hex: 0x8A5CF5)
    static let tagText = Color(hex: 0xA88BFA)
    static let tagBackground = Color(hex: 0x8A5CF5).opacity(0.15)

    static let red = Color(hex: 0xFB464C)
    static let orange = Color(hex: 0xE9973F)
    static let blue = Color(hex: 0x53A6FF)

    static let titlebarHeight: CGFloat = 38
    static let windowBackground = NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, alpha: 1)
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
    init(task: TaskItem) {
        self = QueueLevel(rawValue: task.queueLevel) ?? .medium
    }

    var title: String {
        switch self {
        case .high: "Urgent"
        case .medium: "Standard"
        case .low: "Someday"
        }
    }

    var color: Color {
        switch self {
        case .high: Theme.red
        case .medium: Theme.orange
        case .low: Theme.blue
        }
    }
}

enum CategoryStyle {
    /// "Things to buy" → "#things-to-buy", rendered like an Obsidian tag.
    static func tag(_ categoryName: String) -> String {
        "#" + categoryName.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    static func symbol(_ categoryName: String) -> String {
        switch categoryName {
        case TaskCategory.thingsToBuy: "cart"
        case TaskCategory.peopleToCall: "phone"
        default: "checklist"
        }
    }
}
