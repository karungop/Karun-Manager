import AppKit
import KarunManagerCore
import SwiftUI

struct TagPill: View {
    let categoryName: String

    var body: some View {
        Text(CategoryStyle.tag(categoryName))
            .lineLimit(1)
            .fixedSize()
            .font(.system(size: 12))
            .foregroundStyle(Theme.tagText)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.tagBackground))
    }
}

struct QueueBadge: View {
    let level: QueueLevel

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(level.color).frame(width: 6, height: 6)
            Text(level.title)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.textMuted)
    }
}

/// Obsidian's `<kbd>` chip.
struct KbdChip: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
    }
}

struct ObsidianButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent ? Color.white : Theme.textNormal)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(prominent ? Theme.accent : Color.white.opacity(0.07))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// Square icon button used in the ribbon and pane headers.
struct IconButton: View {
    let symbol: String
    let help: String
    var isActive = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(isActive ? Theme.textNormal : Theme.textMuted)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Theme.selected : hovering ? Theme.hover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct Checkbox: View {
    let isChecked: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isChecked ? Theme.accent : .clear)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isChecked ? Theme.accent : hovering ? Theme.accent : Theme.textFaint, lineWidth: 1.5)
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct VLine: View {
    var body: some View { Theme.border.frame(width: 1) }
}

struct HLine: View {
    var body: some View { Theme.border.frame(height: 1) }
}

/// Lets the custom (titlebar-less) header strips drag the window and double-click to zoom.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Menu items for picking a `RepeatRule`, with a checkmark on the current one.
struct RepeatRuleMenuItems: View {
    let current: RepeatRule
    let onSelect: (RepeatRule) -> Void

    var body: some View {
        ForEach(RepeatRule.allCases, id: \.self) { rule in
            Button {
                onSelect(rule)
            } label: {
                if rule == current {
                    Label(rule.title, systemImage: "checkmark")
                } else {
                    Text(rule.title)
                }
            }
            if rule == .never { Divider() }
        }
    }
}

/// Accent outline shown on whatever a dragged task is hovering over.
struct DropHighlight: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Theme.accent.opacity(0.08) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isActive ? Theme.accent.opacity(0.7) : .clear, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                )
        )
    }
}

extension View {
    func dropHighlight(_ isActive: Bool) -> some View { modifier(DropHighlight(isActive: isActive)) }
}

/// The category as a tag chip that opens a menu of categories.
struct CategoryMenu: View {
    let categories: [String]
    @Binding var selection: String

    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(categories, id: \.self) { name in
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
