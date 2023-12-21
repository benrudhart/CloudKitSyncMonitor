import Foundation
import CloudKit
import CoreData

@Observable
final class CloudStateManager {
    private(set) var setupState: SyncState = .notStarted
    private(set) var importState: SyncState = .notStarted
    private(set) var exportState: SyncState = .notStarted

    private var allSyncStates: [SyncState] {
        [setupState, importState, exportState]
    }

    // MARK: - Listeners -

    private var observeTask: Task<Void, Never>?

    init() {}

    func observeSyncStates() {
        observeTask?.cancel()
        observeTask = Task { await setupCloudKitStateListener() }
    }

    /// Monitors `NSPersistentCloudKitContainer` sync events
    @MainActor
    private func setupCloudKitStateListener() async {
        let eventStream = NotificationCenter.default
            .notifications(named: NSPersistentCloudKitContainer.eventChangedNotification)
            .compactMap { notification in
                let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                return event as? NSPersistentCloudKitContainer.Event
            }

        for await event in eventStream {
            setState(from: event)
        }
    }

    /// Set the appropriate State property (importState, exportState, setupState) based on the provided event
    @MainActor
    func setState(from event: SyncEvent) {
        let state = SyncState(event: event)

        switch event.type {
        case .setup:
            setupState = state
        case .import:
            importState = state
        case .export:
            exportState = state
        @unknown default:
            assertionFailure("NSPersistentCloudKitContainer added a new event type.")
        }
    }
}
