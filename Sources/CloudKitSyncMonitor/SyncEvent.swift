import CoreData

/// A sync event containing the values from NSPersistentCloudKitContainer.Event that we track
struct SyncEvent {
    let type: NSPersistentCloudKitContainer.EventType
    let startDate: Date?
    let endDate: Date?
    let succeeded: Bool
    let error: Error?

    /// For testing purposes. Creates a SyncEvent from explicitly provided values.
    init(type: NSPersistentCloudKitContainer.EventType, startDate: Date?, endDate: Date?, succeeded: Bool,
         error: Error?) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.succeeded = succeeded
        self.error = error
    }

    /// Creates a SyncEvent from an NSPersistentCloudKitContainer Event
    init(from cloudKitEvent: NSPersistentCloudKitContainer.Event) {
        self.type = cloudKitEvent.type
        self.startDate = cloudKitEvent.startDate
        self.endDate = cloudKitEvent.endDate
        self.succeeded = cloudKitEvent.succeeded
        self.error = cloudKitEvent.error
    }
}
