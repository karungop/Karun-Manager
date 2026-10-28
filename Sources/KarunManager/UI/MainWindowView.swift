import KarunManagerCore
import SwiftData
import SwiftUI

struct MainWindowView: View {
    @Bindable var model: LibraryModel

    @Query(sort: [SortDescriptor(\TaskItem.queueLevel), SortDescriptor(\TaskItem.createdAt)])
    private var tasks: [TaskItem]

    var body: some View {
        HStack(spacing: 0) {
            RibbonView(model: model)
            VLine()
            SidebarView(model: model, tasks: tasks)
                .frame(width: 240)
            VLine()
            TaskListPane(model: model, tasks: tasks)
                .frame(minWidth: 440, maxWidth: .infinity)
            VLine()
            InspectorPane(model: model, tasks: tasks)
                .frame(width: 280)
        }
        .overlay(alignment: .bottomTrailing) {
            StatusBarView(model: model, tasks: tasks)
        }
        .background(Theme.bgPrimary)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 1040, minHeight: 600)
    }
}

/// Obsidian's thin far-left icon strip. Traffic lights sit in its top inset.
struct RibbonView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        VStack(spacing: 6) {
            WindowDragArea().frame(height: Theme.titlebarHeight)
            IconButton(symbol: "square.and.pencil", help: "Quick capture (⌥Space)") { model.onQuickCapture() }
            IconButton(symbol: "bolt", help: "Nudge me now") { model.onNudgeNow() }
            IconButton(symbol: "tray.full", help: "All open tasks", isActive: model.selection == .allOpen) {
                model.selection = .allOpen
            }
            IconButton(symbol: "checkmark.circle", help: "Completed", isActive: model.selection == .completed) {
                model.selection = .completed
            }
            Spacer()
        }
        .frame(width: 44)
        .padding(.bottom, 10)
        .background(Theme.bgSecondary)
    }
}

/// Bottom-right status strip, like Obsidian's word count / sync indicator.
struct StatusBarView: View {
    let model: LibraryModel
    let tasks: [TaskItem]

    var body: some View {
        let open = tasks.filter { !$0.isCompleted }
        let urgent = open.filter { $0.queueLevel == QueueLevel.high.rawValue }.count

        TimelineView(.everyMinute) { _ in
            HStack(spacing: 14) {
                Text("\(open.count) open")
                Text("\(urgent) urgent")
                if let last = model.lastNudgeAt {
                    Text("last nudge \(last, format: .relative(presentation: .named))")
                } else {
                    Text("no nudges yet")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 6)
                    .fill(Theme.bgSecondary)
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 6).strokeBorder(Theme.border))
            )
        }
    }
}
