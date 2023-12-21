import Foundation
import CloudKit
import CoreData

@Observable
public final class CloudKitStateManager: CloudKitStateObserver {
    public func syncState(stateType: NSPersistentCloudKitContainer.EventType) -> SyncState {
        switch stateType {
        case .setup:
            return setupState
        case .import:
            return importState
        case .export:
            return exportState
        @unknown default:
            assertionFailure()
            return setupState
        }
    }

    public private(set) var setupState: SyncState
    public private(set) var importState: SyncState
    public private(set) var exportState: SyncState

    var allStates: [SyncState] {
        [setupState, importState, exportState]
    }

    /// Contains the last Error encountered.
    ///
    /// This can be helpful in diagnosing "notSyncing" issues or other "partial error"s from which CloudKit thinks it recovered, but didn't really.
    var lastError: Error? {
        let errorDates = allStates.compactMap { state in
            if case let .failed(_, endDate, error) = state {
                return (date: endDate, error: error)
            } else {
                return nil
            }
        }

        return errorDates
            .sorted { $0.date > $1.date }
            .first?.error
    }

    public var syncStateSummary: SyncSummaryStatus {
        if let lastError {
            return .error(lastError)
        }

        if allStates.contains(where: { $0.inProgress }) {
            return .inProgress
        }

        switch (setupState, importState, exportState) {
        case (.succeeded, .undetermined, .undetermined):
            return .notSyncing

        case (.succeeded, .succeeded, .succeeded):
            return .succeeded

        case (.undetermined, .succeeded, .succeeded):
            // sometimes no `.setup` event is emitted. Ignore those cases
            return .succeeded

        default:
            return .unknown
        }
    }

    private var observeTask: Task<Void, Never>?

    init(
        setupState: SyncState = .undetermined,
        importState: SyncState = .undetermined,
        exportState: SyncState = .undetermined
    ) {
        self.setupState = setupState
        self.importState = importState
        self.exportState = exportState
    }

    public func observeSyncStates() {
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
