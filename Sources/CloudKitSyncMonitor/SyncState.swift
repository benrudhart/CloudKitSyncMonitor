import Foundation

/// The state of a CloudKit import, export, or setup event as reported by an `NSPersistentCloudKitContainer` notification
public enum SyncState {
    /// No event has been reported
    case notStarted

    /// A notification with a start date was received, but it had no end date.
    case inProgress(started: Date)

    /// The last sync of this type finished and succeeded (`succeeded` was `true` in the notification from `NSPersistentCloudKitContainer`).
    case succeeded(started: Date, ended: Date)

    /// The last sync of this type finished but failed (`succeeded` was `false` in the notification from `NSPersistentCloudKitContainer`).
    case failed(started: Date, ended: Date, error: Error?)

    /// Convenience property that returns true if the last sync of this type succeeded
    ///
    /// `succeeded` is true if the sync finished and reported true for its "succeeded" property.
    /// Otherwise (e.g.
    var succeeded: Bool {
        if case .succeeded = self { return true }
        return false
    }

    /// Convenience property that returns true if the last sync of this type failed
    var failed: Bool {
        if case .failed = self { return true }
        return false
    }

    /// Convenience property that returns the error returned if the event failed
    ///
    /// This is the main property you'll want to use to detect an error, as it will be `nil` if the sync is incomplete or succeeded, and will contain
    /// an `Error` if the sync finished and failed.
    ///
    ///     if let error = SyncMonitor.shared.exportState.error {
    ///         print("Sync failed: \(error.localizedDescription)")
    ///     }
    ///
    /// Note that this property will report all errors, including those caused by normal things like being offline.
    /// See also `SyncMonitor.importError` and `SyncMonitor.exportError` for more intelligent error reporting.
    var error: Error? {
        if case let .failed(_,_,error) = self, let e = error {
            return e
        }
        return nil
    }
}

extension SyncState {
    init(event: SyncEvent) {
        if let startDate = event.startDate {
            // NSPersistentCloudKitContainer sends a notification when an event starts, and another when it
            // ends. If it has an endDate, it means the event finished.
            if let endDate = event.endDate {
                if event.succeeded {
                    self = .succeeded(started: startDate, ended: endDate)
                } else {
                    self = .failed(started: startDate, ended: endDate, error: event.error)
                }
            } else {
                self = .inProgress(started: startDate)
            }
        } else {
            self = .notStarted
        }
    }
}
