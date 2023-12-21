//
//  SyncMonitor.swift
//  
//
//  Created by Grant Grueninger on 9/23/20.
//

import Foundation

@available(iOS 17.0, macCatalyst 14.0, OSX 11, tvOS 14.0, watchOS 10, *)
@Observable
public final class SyncMonitor {
    /// A singleton to use
    public static let shared = SyncMonitor()

    // MARK: - Summary properties -

    /// Returns an overview of the state of sync, which you could use to display a summary icon
    ///
    /// The general sync state is detmined as follows:
    /// - If the network isn't available, the state summary is `.noNetwork`.
    /// - Otherwise, if the iCloud account isn't available (e.g. they're not logged in or have disabled iCloud for the app in Settings or System Preferences), the
    ///     state summary is`.accountNotAvailable`.
    /// - Otherwise, if `NSPersistentCloudKitContainer` reported an error for any event type the last time that event type ran, the state summary is
    ///     `.error`.
    /// - Otherwise, if `notSyncing` is true, the state is `.notSyncing`.
    /// - Otherwise, if all event types are `.notStarted`, the state is `.notStarted`.
    /// - Otherwise, if any event type is `.inProgress`, the state is `.inProgress`.
    /// - Otherwise, if all event types are `.successful`, the state is `.succeeded`.
    /// - Otherwise, the state is `.unknown`.
    ///
    /// Here's how you might use this in a SwiftUI view:
    ///
    ///     @ObservedObject var syncMonitor: SyncMonitor = SyncMonitor.shared
    ///
    ///     Image(systemName: syncMonitor.syncStateSummary.symbolName)
    ///         .foregroundColor(syncMonitor.syncStateSummary.symbolColor)
    ///
    /// Or maybe you only want to show errors:
    ///
    ///     if syncMonitor.syncStateSummary.isBroken {
    ///         Image(systemName: syncMonitor.syncStateSummary.symbolName)
    ///             .foregroundColor(syncMonitor.syncStateSummary.symbolColor)
    ///     }
    ///
    /// Or, only show an icon when syncing is happening:
    ///
    ///     // See http://goshdarnifcaseletsyntax.com for "if case" help. :)
    ///     if case .inProgress = syncMonitor.syncStateSummary {
    ///         Image(systemName: syncMonitor.syncStateSummary.symbolName)
    ///             .foregroundColor(syncMonitor.syncStateSummary.symbolColor)
    ///     }
    ///
    public var syncStateSummary: SyncSummaryStatus {
        if isNetworkAvailable == false {
            return .noNetwork
        }

        if ckAccountManager.accountStatus != .available {
            return .accountNotAvailable
        }
        
        if syncError {
            return .error
        }
        
        if notSyncing {
            return .notSyncing
        }

        if [importState, exportState].allSatisfy({ $0.notStarted }) {
            return .notStarted
        }

        if allSyncStates.contains(where: { $0.inProgress }) {
            return .inProgress
        }

        if allSyncStates.allSatisfy({ $0.succeeded }) {
            return .succeeded
        }


        return .unknown
    }

    /// Returns true if `NSPersistentCloudKitContainer` has reported an error.
    ///
    /// This is a convenience property that returns true if `setupError`, `importError` or `exportError` is not nil.
    /// If `syncError` is true, then either `setupError`, `importError` or `exportError` (or any combination of them)) will contain an error object.
    ///
    ///     // If true, either setupError, importError or exportError will contain an error
    ///     if SyncMonitor.shared.syncError {
    ///         if let e = SyncMonitor.shared.setupError {
    ///             print("Unable to set up iCloud sync, changes won't be saved! \(e.localizedDescription)")
    ///         }
    ///         if let e = SyncMonitor.shared.importError {
    ///             print("Import is broken: \(e.localizedDescription)")
    ///         }
    ///         if let e = SyncMonitor.shared.exportError {
    ///             print("Export is broken - your changes aren't being saved! \(e.localizedDescription)")
    ///         }
    ///     }
    ///
    /// `syncError` being `true` means that `NSPersistentCloudKitContainer` sent a notification that included an error.
    public var syncError: Bool {
        isNetworkAvailable == true && lastError != nil
    }

    /// Returns `true` if there's no reason that we know of why sync shouldn't be working
    ///
    /// That is, the user's iCloud account status is "available", the network is available, there are no recorded sync errors, and setup is complete and succeeded.
    public var shouldBeSyncing: Bool {
        if case .available = ckAccountManager.accountStatus,
           isNetworkAvailable == true,
           !syncError,
           case .succeeded = setupState {
            return true
        }

        return false
    }

    /// Detects a condition in which CloudKit _should_ be syncing, but isn't.
    ///
    /// `notSyncing` is true if `shouldBeSyncing` is true (see `shouldBeSyncing`) but `importState` is still `.notStarted`.
    ///
    /// The first thing `NSPersistentCloudKitContainer`does when the app starts is to set up, then run an import. So, `notSyncing` should be true for
    /// a very very short period of time (e.g. less than a second) for the time between when setup completes and the import starts. As such, it's suitable for
    /// displaying an error graphic to the user, e.g. `Image(systemName: "xmark.icloud")` if `notSyncing` is `true`, but not necessarily for
    /// programmatic action (unless notSyncing stays true for more than a few seconds).
    ///
    ///     if SyncMonitor.shared.syncError {
    ///         // Act on error
    ///     } else if SyncMonitor.shared.notSyncing {
    ///         print("Sync should be working, but isn't. Look for a badge on Settings or other possible issues.")
    ///     }
    ///
    /// I would argue that `notSyncing` being `true` for a longer period of time indicates a bug in `NSPersistentCloudKitContainer`. E.g. the case
    /// that made me write this computed property is that if Settings on iOS wants the user to log in again, CloudKit will report a "partial error" when setting up,
    /// but ultimately send a notifiation stating that setup was successful; however, CloudKit will then just not sync, providing no errors. `notSyncing` detects
    /// this condition, and those like it. If you see `notSyncing` being triggered, I'd recommend isolating the issue (e.g. the one above) and filing a FB about it
    /// to Apple.
    public var notSyncing: Bool {
        if case .notStarted = importState, shouldBeSyncing {
            return true
        }
        return false
    }

    /// If not `nil`, there is a real problem encountered when CloudKit was trying to set itself up
    ///
    /// This means `NSPersistentCloudKitContainer` probably won't try to do imports or exports, which means that data won't be synced. However, it's
    /// usually caused by something that can be fixed without deleting the DB, so it usually means that sync will just be delayed, unlike exportError, which
    /// usually requires deleting the local DB, thus losing changes.
    ///
    /// You should examine the error for the cause. You may then be able to at least report it to the user, if not automate a "fix" in your app.
    public var setupError: Error? {
        if isNetworkAvailable == true, let error = setupState.error {
            return error
        }
        return nil
    }

    /// If not `nil`, there is a problem with CloudKit's import.
    public var importError: Error? {
        if isNetworkAvailable == true, let error = importState.error {
            return error
        }
        return nil
    }

    /// If not `nil`, there is a real problem with CloudKit's export
    ///
    ///     if let error = SyncMonitor.shared.exportError {
    ///         print("Something needs to be fixed: \(error.localizedDescription)")
    ///     }
    ///
    /// This method is the main reason this module exists. When NSPersistentCloudKitContainer "stops working", it's because it's hit an error from which it
    /// can not recover. If that error happens during an export, it means your user's probably going to lose any changes they make (since iCloud is the
    /// "source of truth", and NSPersistentCloudKitContainer can't get their changes to iCloud).
    /// The key to data safety, then, is to detect and correct the error immediately. `exportError` is designed to detect this unrecoverable error state
    /// the moment it happens. It specifically tests that the network is available and that an error was reported (including error text). This means that sync
    /// _should_ be working (that is, they're online), but failed. The user, or your application, will likely need to take action to correct the problem.
    public var exportError: Error? {
        if isNetworkAvailable == true, let error = exportState.error {
            return error
        }
        return nil
    }

    // MARK: - Specific Status Properties -
    let cloudStateManager = CloudStateManager()

    /// The state of `NSPersistentCloudKitContainer`'s "setup" event
    public var setupState: SyncState {
        cloudStateManager.setupState
    }

    /// The state of `NSPersistentCloudKitContainer`'s "import" event
    public var importState: SyncState {
        cloudStateManager.importState
    }

    /// The state of `NSPersistentCloudKitContainer`'s "export" event
    public var exportState: SyncState {
        cloudStateManager.exportState
    }

    /// Returns `true` if the network is available in any capacity (Wi-Fi, Ethernet, cellular, carrier pidgeon, etc) - we just care if we can reach iCloud.
    public var isNetworkAvailable: Bool {
        networkMonitor.isNetworkAvailable
    }

    private var networkMonitor: NetworkMonitor = NetworkManager()
    private let ckAccountManager = CKAccountManager()

    // MARK: - Diagnosis properties -

    /// Contains the last Error encountered.
    ///
    /// This can be helpful in diagnosing "notSyncing" issues or other "partial error"s from which CloudKit thinks it recovered, but didn't really.
    public var lastError: Error? {
        let errorDates = allSyncStates.compactMap { state in
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

    private var allSyncStates: [SyncState] {
        [setupState, importState, exportState]
    }

    // MARK: - Listeners -

    private var observeTask: Task<Void, Never>?

    // MARK: - Initializers

    /// Creates a new sync monitor and sets up listeners to sync and network changes
    public init(setupState: SyncState = .notStarted, 
                importState: SyncState = .notStarted,
                exportState: SyncState = .notStarted,
                lastErrorText: String? = nil,
                listen: Bool = true) {
        guard listen else { return }

        observeStates()
    }

    func observeStates() {
        networkMonitor.startObserving()
        cloudStateManager.observeSyncStates()
        ckAccountManager.startObserving()
    }
}

extension SyncMonitor {
    /// For Testing Purposes: Convenience initializer that creates a SyncMonitor with preset state values for testing or previews
    convenience init(
        setupSuccessful: Bool = true,
        importSuccessful: Bool? = true,
        exportSuccessful: Bool = true,
        networkAvailable: Bool = true,
        isCKAccountAvailable: Bool = true,
        errorText: String? = nil,
        listen: Bool
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

        self.init(setupState: setupState, importState: importState, exportState: exportState, lastErrorText: errorText, listen: listen)
        
        self.networkMonitor = NetworkMonitorMock(isNetworkAvailable: networkAvailable)
//        self.iCloudAccountStatus = iCloudAccountStatus

        struct NetworkMonitorMock: NetworkMonitor {
            var isNetworkAvailable: Bool
            func startObserving() {}
        }
    }
}
