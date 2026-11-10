import CoreData
import Foundation
import Security

/// iCloud sync availability for this build and user, and the hook for changes arriving from other devices.
@MainActor
final class CloudSync {
    enum Status: Equatable {
        /// Tasks and preferences sync through this iCloud container.
        case on(container: String)
        /// The build isn't signed with the iCloud entitlement (see README → iCloud sync).
        case notEntitled
        /// Entitled, but no iCloud account is signed in on this Mac; tasks stay local until one is.
        case noAccount(container: String)
        /// A throwaway (`--in-memory` / `--demo`) run.
        case disabledForSession
    }

    let status: Status
    /// The container to hand to `TaskStore.makeContainer`, or nil to keep the store local.
    var containerIdentifier: String? {
        switch status {
        case .on(let id), .noAccount(let id): id  // syncs once an account appears; no store rebuild needed
        case .notEntitled, .disabledForSession: nil
        }
    }

    private var observer: NSObjectProtocol?
    private var pending: DispatchWorkItem?

    init(inMemory: Bool) {
        guard !inMemory else { status = .disabledForSession; return }
        guard let container = Self.entitledContainers().first else { status = .notEntitled; return }
        status = FileManager.default.ubiquityIdentityToken == nil ? .noAccount(container: container) : .on(container: container)
    }

    /// Calls `handler` on the main actor after iCloud imports changes into the task store. Imports arrive in
    /// bursts, so calls are coalesced (one per half second).
    func observeRemoteChanges(_ handler: @escaping @MainActor () -> Void) {
        guard containerIdentifier != nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pending?.cancel()
                let work = DispatchWorkItem { MainActor.assumeIsolated(handler) }
                self.pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            }
        }
    }

    /// iCloud containers in this process's code signature. Signing with the entitlement but without a
    /// matching provisioning profile makes macOS refuse to launch the app, so this being non-empty means
    /// the build was set up for iCloud on purpose.
    private static func entitledContainers() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil)
        else { return [] }
        return (value as? [String]) ?? []
    }
}
