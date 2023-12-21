import CoreData

/// A sync event containing the values from NSPersistentCloudKitContainer.Event that we track
protocol SyncEvent {
    var type: NSPersistentCloudKitContainer.EventType { get }
    var startDate: Date { get }
    var endDate: Date? { get }
    var succeeded: Bool { get }
    var error: Error? { get }
}

extension NSPersistentCloudKitContainer.Event: SyncEvent {}
