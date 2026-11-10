import SwiftUI

/// Karun Manager for iPhone: a companion to the Mac app for capturing and clearing tasks on the go.
/// Deliberately small. You can add, complete and delete tasks. Settings, categories, skip rules, nudges,
/// repeats and due dates are managed on the Mac and sync here through iCloud.
@main
struct KarunManagerMobileApp: App {
    @State private var model = MobileModel()

    var body: some Scene {
        WindowGroup {
            TaskListView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(MobileTheme.accent)
        }
    }
}
