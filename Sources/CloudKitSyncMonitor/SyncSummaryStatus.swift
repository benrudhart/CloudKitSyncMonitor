import SwiftUI

/// Possible values for the summary of the state of iCloud sync
public enum SyncSummaryStatus {
    case noNetwork
    case accountNotAvailable
    case error
    case notSyncing
    case notStarted
    case inProgress
    case succeeded
    case unknown
}

extension SyncSummaryStatus {
    /// SF symbol name you can use to display the status
    public var symbolName: String {
        switch self {
        case .noNetwork:
            return "bolt.horizontal.icloud"
        case .accountNotAvailable:
            return "icloud.slash"
        case .error:
            return "exclamationmark.icloud"
        case .notSyncing:
            return "xmark.icloud"
        case .notStarted:
            return "bolt.horizontal.icloud"
        case .inProgress:
            return "arrow.triangle.2.circlepath.icloud"
        case .succeeded:
            return "checkmark.icloud"
        case .unknown:
            return "bolt.horizontal.icloud"
        }
    }

    // A string you could use to display the status
    public var description: String {
        switch self {
        case .noNetwork:
            return "No network available"
        case .accountNotAvailable:
            return "No iCloud account"
        case .error:
            return "Error"
        case .notSyncing:
            return "Not syncing to iCloud"
        case .notStarted:
            return "Sync not started"
        case .inProgress:
            return "Syncing..."
        case .succeeded:
            return "Synced with iCloud"
        case .unknown:
            return "Error"
        }
    }

    /// A SwiftUI Color you can use for the symbol
    public var symbolColor: Color {
        switch self {
        case .noNetwork:
            return .gray
        case .accountNotAvailable:
            return .gray
        case .error:
            return .red
        case .notSyncing:
            return .red
        case .notStarted:
            return .gray
        case .inProgress:
            return .gray
        case .succeeded:
            return .green
        case .unknown:
            return .red
        }
    }

    /// Returns true if the state indicates that sync is broken
    public var isBroken: Bool {
        switch self {
        case .noNetwork, .accountNotAvailable, .notStarted, .inProgress, .succeeded:
            return false
        case .error, .notSyncing, .unknown:
            return true
        }
    }

    /// Convenience accessor that returns true if a sync is in progress
    ///
    /// This lets you do things like `if SyncMonitor.shared.broken || SyncMonitor.shared.inProgress { ... }`,
    /// since Swift doesn't like `case` statements intermixed into if statements.
    public var inProgress: Bool {
        if case .inProgress = self {
            return true
        }
        return false
    }
}
