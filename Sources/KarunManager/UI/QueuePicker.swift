import KarunManagerCore
import SwiftUI

/// Segmented Urgent / Standard / Someday control.
struct QueuePicker: View {
    let selection: QueueLevel
    /// Stretch segments to fill the available width (inspector) instead of hugging labels (composer).
    var fillsWidth = false
    let onSelect: (QueueLevel) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(QueueLevel.allCases, id: \.self) { level in
                let isSelected = level == selection
                Button {
                    onSelect(level)
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(level.color).frame(width: 6, height: 6)
                        Text(level.title).lineLimit(1)
                    }
                    .fixedSize()
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.textNormal : Theme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? Theme.selected : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("⌘\(level.rawValue + 1)")
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
    }
}

/// The queue badge on a task row, clickable to move the task to another queue.
struct QueueMenu: View {
    let task: TaskItem
    let onSelect: (QueueLevel) -> Void

    @State private var hovering = false

    var body: some View {
        let current = QueueLevel(task: task)
        Menu {
            ForEach(QueueLevel.allCases, id: \.self) { level in
                Button {
                    onSelect(level)
                } label: {
                    if level == current {
                        Label(level.title, systemImage: "checkmark")
                    } else {
                        Text(level.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                QueueBadge(level: current)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(hovering ? Theme.textMuted : Theme.textFaint)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Change queue")
    }
}
