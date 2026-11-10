import KarunManagerCore
import SwiftUI

/// The whole app: open tasks grouped by queue, a composer at the bottom, swipe right to complete and
/// swipe left to delete.
struct TaskListView: View {
    @Environment(MobileModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var completions = 0

    var body: some View {
        NavigationStack {
            List {
                if let problem = model.problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(MobileTheme.orange)
                            .listRowBackground(MobileTheme.bgSecondary)
                    }
                }
                ForEach(QueueLevel.allCases, id: \.self) { level in
                    let tasks = model.tasks(in: level)
                    if !tasks.isEmpty {
                        Section {
                            ForEach(tasks, id: \.id) { task in
                                row(for: task)
                            }
                        } header: {
                            QueueHeader(level: level, count: tasks.count)
                        }
                    }
                }
                if !model.tasks.isEmpty {
                    Section {} footer: {
                        Text("Swipe right to complete, left to delete. Categories, repeats, due dates and nudges are managed in Karun Manager on your Mac.")
                            .font(.footnote)
                            .foregroundStyle(MobileTheme.textFaint)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(MobileTheme.bgPrimary)
            .overlay {
                if model.tasks.isEmpty {
                    ContentUnavailableView(
                        "All clear",
                        systemImage: "checkmark.circle",
                        description: Text("Nothing open. Add a task below.")
                    )
                    .foregroundStyle(MobileTheme.textMuted)
                }
            }
            .navigationTitle("Karun Manager")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SyncBadge(status: model.syncStatus) }
            }
            .toolbarBackground(MobileTheme.bgPrimary, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if let undo = model.undo {
                        UndoBanner(message: undo.message, onUndo: model.performUndo)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    ComposerBar()
                }
                .animation(.snappy, value: model.undo?.id)
            }
        }
        .sensoryFeedback(.success, trigger: completions)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reload() }
        }
    }

    private func row(for task: TaskItem) -> some View {
        TaskRow(task: task, isUpNext: task.id == model.upNextID) { complete(task) }
            .listRowBackground(MobileTheme.bgSecondary)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { complete(task) } label: { Label("Done", systemImage: "checkmark") }
                    .tint(MobileTheme.green)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    withAnimation { model.delete(task) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                Button { complete(task) } label: { Label("Done", systemImage: "checkmark") }
                Button(role: .destructive) {
                    withAnimation { model.delete(task) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private func complete(_ task: TaskItem) {
        withAnimation { model.complete(task) }
        completions += 1
    }
}

private struct QueueHeader: View {
    let level: QueueLevel
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(level.color).frame(width: 8, height: 8)
            Text(level.title).foregroundStyle(MobileTheme.textNormal)
            Text("\(count)").foregroundStyle(MobileTheme.textFaint)
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }
}

struct TaskRow: View {
    let task: TaskItem
    let isUpNext: Bool
    let onComplete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(MobileTheme.textFaint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .foregroundStyle(MobileTheme.textNormal)
                details
            }
        }
        .padding(.vertical, 2)
    }

    /// Read-only hints about properties that are edited on the Mac.
    private var details: some View {
        HStack(spacing: 8) {
            Text("#" + CaptureParser.slug(task.categoryName))
                .foregroundStyle(MobileTheme.tagText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(MobileTheme.tagBackground, in: Capsule())
            if isUpNext {
                Label("Up next", systemImage: "bolt.fill")
                    .foregroundStyle(MobileTheme.accent)
            }
            if task.repeatRule != .never {
                Image(systemName: "repeat").foregroundStyle(MobileTheme.textFaint)
                    .accessibilityLabel("Repeats")
            }
            if let due = task.dueDate {
                Label(due.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
                    .foregroundStyle(due < .now ? MobileTheme.red : MobileTheme.textMuted)
            }
            if task.isSnoozed(at: .now) {
                Image(systemName: "moon.zzz").foregroundStyle(MobileTheme.textFaint)
                    .accessibilityLabel("Snoozed")
            }
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }
}

private struct UndoBanner: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .lineLimit(1)
                .foregroundStyle(MobileTheme.textNormal)
            Spacer()
            Button("Undo", action: onUndo)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MobileTheme.bgSecondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MobileTheme.border))
        .padding(.horizontal)
    }
}

/// A cloud icon in the toolbar; tap it for a one-line explanation of where tasks live.
private struct SyncBadge: View {
    let status: MobileModel.SyncStatus

    var body: some View {
        Menu {
            Text(explanation)
        } label: {
            Image(systemName: symbol)
                .foregroundStyle(status == .on ? MobileTheme.textMuted : MobileTheme.orange)
        }
        .accessibilityLabel("Sync status")
    }

    private var symbol: String {
        switch status {
        case .on: "checkmark.icloud"
        case .noAccount: "exclamationmark.icloud"
        case .off: "icloud.slash"
        case .demo: "testtube.2"
        }
    }

    private var explanation: String {
        switch status {
        case .on: "Syncing with your Mac through iCloud."
        case .noAccount: "Sign in to iCloud in Settings to sync with your Mac. Tasks stay on this iPhone until then."
        case .off: "This build doesn't use iCloud, so tasks stay on this iPhone."
        case .demo: "Demo mode: sample tasks, nothing is saved."
        }
    }
}
