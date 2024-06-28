import Foundation
import CoreData

@MainActor
public protocol CloudKitStateObserver: Sendable {
    var setupState: SyncState { get }
    var importState: SyncState { get }
    var exportState: SyncState { get }
    var syncStateSummary: SyncSummaryStatus { get }

    func observeSyncStates()
    func syncState(stateType: NSPersistentCloudKitContainer.EventType) -> SyncState
}
