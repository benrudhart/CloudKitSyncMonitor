@testable import CloudKitSyncMonitor
import CoreData
import Foundation

extension SyncMonitor {
    /// For Testing Purposes: Convenience initializer that creates a SyncMonitor with preset state values for testing or previews
    convenience init(
        setupSuccessful: Bool = true,
        importSuccessful: Bool? = true,
        exportSuccessful: Bool = true,
        networkAvailable: Bool = true,
        isCKAccountAvailable: Bool = true,
        errorText: String? = nil
    ) {
        let error = errorText.map { NSError(domain: $0, code: 0, userInfo: nil) }
        let startDate = Date(timeIntervalSinceNow: -15) // a 15 second sync. :o
        let endDate = Date.now

        let setupState: SyncState = setupSuccessful
            ? SyncState.succeeded(started: startDate, ended: endDate)
            : .failed(started: startDate, ended: endDate, error: error)

        let importState: SyncState
        switch importSuccessful {
        case .none:
            importState = .notStarted
        case .some(true):
            importState = .succeeded(started: startDate, ended: endDate)
        case .some(false):
            importState = .failed(started: startDate, ended: endDate, error: error)
        }

        let exportState: SyncState = exportSuccessful
            ? .succeeded(started: startDate, ended: endDate)
            : .failed(started: startDate, ended: endDate, error: error)

        let networkMonitor = NetworkMonitorMock(isNetworkAvailable: networkAvailable)
        let ckStateObserver = CKStateObserverMock(setupState: setupState, importState: importState, exportState: exportState)
        
        self.init(
            networkMonitor: networkMonitor,
            ckStateObserver: ckStateObserver
        )
    }
}

struct CKStateObserverMock: CloudKitStateObserver {
    var setupState: CloudKitSyncMonitor.SyncState
    var importState: CloudKitSyncMonitor.SyncState
    var exportState: CloudKitSyncMonitor.SyncState
    var syncStateSummary: CloudKitSyncMonitor.SyncSummaryStatus = .unknown

    func observeSyncStates() {}
    
    func syncState(stateType: NSPersistentCloudKitContainer.EventType) -> CloudKitSyncMonitor.SyncState {
        .notStarted
    }
}

struct NetworkMonitorMock: NetworkMonitor {
    var isNetworkAvailable: Bool
    func startObserving() {}
}
