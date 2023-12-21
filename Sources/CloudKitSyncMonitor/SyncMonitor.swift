//
//  SyncMonitor.swift
//  
//
//  Created by Grant Grueninger on 9/23/20.
//

import CoreData
import Network
import CloudKit

/// An object, usually used as a singleton, that provides, and publishes, the current state of `NSPersistentCloudKitContainer`'s sync
///
/// This class is overkill when it comes to reporting on iCloud sync. Normally, `NSPersistentCloudKitContainer` will sync happily and you can
/// leave it alone. Every once in a while, however, it will hit an error that makes it stop syncing. This is what you really want to detect, because, since iCloud
/// is the "source of truth" for your `NSPersistentCloudKitContainer` data, a sync failure can mean data loss.
///
/// Here are the basics:
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
///     } else if SyncMonitor.shared.notSyncing {
///         print("Sync should be working, but isn't. Look for a badge on Settings or other possible issues.")
///     }
///
/// `syncError` and `notSyncing`, together, tell you if there's a problem that `NSPersistentCloudKitContainer` has announced or not announced
/// (respectively).
/// The `setupError`, `importError`, and `exportError` properties can give you the reported error. Digging deeper, `setupState`, `importState`,
/// and `exportState` give you the state of each type of `NSPersistentCloudKitContainer` event in a nice little `SyncState` enum with associated
/// values that let you get even more granular, e.g. to find whether each type of event is in progress, succeeded, or failed,  the start and end time of the event, and
/// any error reported if the event failed.
///
/// *Some example code to use in SwiftUI views*
///
/// First, observe the shared syncmonitor instance so your view will update if the state changes:
///
///     @ObservedObject var syncMonitor: SyncMonitor = SyncMonitor.shared
///
/// Show a sync status icon:
///
///     Image(systemName: syncMonitor.syncStateSummary.symbolName)
///         .foregroundColor(syncMonitor.syncStateSummary.symbolColor)
///
/// Only show an icon if there's a sync error:
///
///     if syncMonitor.syncStateSummary.isBroken {
///         Image(systemName: syncMonitor.syncStateSummary.symbolName)
///             .foregroundColor(syncMonitor.syncStateSummary.symbolColor)
///     }
///
/// Only show an icon when syncing is happening:
///
///     // See http://goshdarnifcaseletsyntax.com for "if case" help. :)
///     if case .inProgress = syncMonitor.syncStateSummary {
///         Image(systemName: syncMonitor.syncStateSummary.symbolName)
///             .foregroundColor(syncMonitor.syncStateSummary.symbolColor)
///     }
///
/// Show a detailed error reporting graphic - shows which type(s) of events are failing.
///
///     Group {
///         if syncMonitor.syncError {
///             VStack {
///                 HStack {
///                     if syncMonitor.setupError != nil {
///                         Image(systemName: "xmark.icloud").foregroundColor(.red)
///                     }
///                     if syncMonitor.importError != nil {
///                         Image(systemName: "icloud.and.arrow.down").foregroundColor(.red)
///                     }
///                     if syncMonitor.exportError != nil {
///                         Image(systemName: "icloud.and.arrow.up").foregroundColor(.red)
///                     }
///                 }
///             }
///         } else if syncMonitor.notSyncing {
///             Image(systemName: "xmark.icloud")
///         } else {
///             Image(systemName: "icloud").foregroundColor(.green)
///         }
///     }
///
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
        if networkAvailable == false { return .noNetwork }
        guard case .available = iCloudAccountStatus else { return .accountNotAvailable }
        if syncError { return .error }
        if notSyncing { return .notSyncing }

        if case .notStarted = importState,
           case .notStarted = exportState,
           case .notStarted = setupState {
            return .notStarted
        }

        if case .inProgress = setupState { return .inProgress }
        if case .inProgress = importState { return .inProgress }
        if case .inProgress = exportState { return .inProgress }

        if case .succeeded = importState, 
            case .succeeded = exportState {
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
        return setupError != nil || importError != nil || exportError != nil
    }

    /// Returns `true` if there's no reason that we know of why sync shouldn't be working
    ///
    /// That is, the user's iCloud account status is "available", the network is available, there are no recorded sync errors, and setup is complete and succeeded.
    public var shouldBeSyncing: Bool {
        if case .available = iCloudAccountStatus,
           networkAvailable == true,
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
    /// You should examime the error for the cause. You may then be able to at least report it to the user, if not automate a "fix" in your app.
    public var setupError: Error? {
        if networkAvailable == true, let error = setupState.error {
            return error
        }
        return nil
    }

    /// If not `nil`, there is a problem with CloudKit's import.
    public var importError: Error? {
        if networkAvailable == true, let error = importState.error {
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
        if networkAvailable == true, let error = exportState.error {
            return error
        }
        return nil
    }

    // MARK: - Specific Status Properties -

    /// The state of `NSPersistentCloudKitContainer`'s "setup" event
    public private(set) var setupState: SyncState = .notStarted

    /// The state of `NSPersistentCloudKitContainer`'s "import" event
    public private(set) var importState: SyncState = .notStarted

    /// The state of `NSPersistentCloudKitContainer`'s "export" event
    public private(set) var exportState: SyncState = .notStarted

    /// Is the network available?
    ///
    /// This is true if the network is available in any capacity (Wi-Fi, Ethernet, cellular, carrier pidgeon, etc) - we just care if we can reach iCloud. 
    public private(set) var networkAvailable: Bool? = nil

    public private(set) var loggedIntoIcloud: Bool? = nil

    /// The current status of the user's iCloud account - updated automatically if they change it
    public private(set) var iCloudAccountStatus: CKAccountStatus

    // MARK: - Diagnosis properties -

    /// Contains the last Error encountered.
    ///
    /// This can be helpful in diagnosing "notSyncing" issues or other "partial error"s from which CloudKit thinks it recovered, but didn't really.
    public private(set) var lastError: Error?

    // MARK: - Listeners -

    private var observeTask: Task<Void, Never>?

    /// Network path monitor that's used to track whether we can reach the network at all
    //    fileprivate let monitor: NetworkMonitor = NWPathMonitor()
    private let monitor = NWPathMonitor()

    /// The queue on which we'll run our network monitor
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")

    // MARK: - Initializers -

    /// Creates a new sync monitor and sets up listeners to sync and network changes
    public init(setupState: SyncState = .notStarted, 
                importState: SyncState = .notStarted,
                exportState: SyncState = .notStarted, 
                networkAvailable: Bool? = nil,
                iCloudAccountStatus: CKAccountStatus? = nil,
                lastErrorText: String? = nil,
                listen: Bool = true) {
        self.setupState = setupState
        self.importState = importState
        self.exportState = exportState
        self.networkAvailable = networkAvailable
        self.iCloudAccountStatus = iCloudAccountStatus ?? .couldNotDetermine
        self.lastError = lastErrorText.map { NSError(domain: $0, code: 0, userInfo: nil) }

        guard listen else { return }

        observeTask = Task {
            await setupCloudKitStateListener()
            await setupiCloudAccountStateListener()
            setupNetworkStateListener()
        }
    }

    /// To make testing possible
    /// Properties need to be set on the main thread for SwiftUI, so we'll do that here
    /// instead of maing setProperties run async code, which is inconvenient for testing.
    @MainActor
    private func setupCloudKitStateListener() async {
        // Monitor NSPersistentCloudKitContainer sync events
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

    /// Update the network status when the OS reports a change. Note that we ignore whether the connection is
    /// expensive or not - we just care whether iCloud is _able_ to sync. If there's no network,
    /// NSPersistentCloudKitContainer will try to sync but report an error. We consider that a real error unless
    /// the network is not available at all. If it's available but expensive, it's still an error.
    /// Ostensively, if the user's device has iCloud syncing turned off (e.g. due to low power mode or not
    /// allowing syncing over cellular connections), NSPersistentCloudKitContainer won't try to sync.
    /// If that assumption is incorrect, we'll need to update the logic in this class.
    private func setupNetworkStateListener() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                #if os(watchOS)
                self.networkAvailable = (path.availableInterfaces.count > 0)
                #else
                self.networkAvailable = (path.status == .satisfied)
                #endif
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Monitor changes to the iCloud account (e.g. login/logout)
    private func setupiCloudAccountStateListener() async  {
        self.iCloudAccountStatus = (try? await CKContainer.default().accountStatus()) ?? .couldNotDetermine

        let stateStream = NotificationCenter.default
            .notifications(named: .CKAccountChanged)
            .map { _ in (try? await CKContainer.default().accountStatus()) ?? .couldNotDetermine }

        for await stateResult in stateStream {
            self.iCloudAccountStatus = stateResult
        }
    }

    // MARK: - Processing NSPersistentCloudKitContainer events -

    /// Set the appropriate State property (importState, exportState, setupState) based on the provided event
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

        if let error = event.error {
            lastError = error
        }
    }
}

extension SyncMonitor {
    /// For Testing Purposes: Convenience initializer that creates a SyncMonitor with preset state values for testing or previews
    convenience init(
        setupSuccessful: Bool = true,
        importSuccessful: Bool = true,
        exportSuccessful: Bool = true,
        networkAvailable: Bool = true,
        iCloudAccountStatus: CKAccountStatus = .available,
        errorText: String?
    ) {
        let error = errorText.map { NSError(domain: $0, code: 0, userInfo: nil) }
        let startDate = Date(timeIntervalSinceNow: -15) // a 15 second sync. :o
        let endDate = Date.now

        let setupState: SyncState = setupSuccessful
            ? SyncState.succeeded(started: startDate, ended: endDate)
            : .failed(started: startDate, ended: endDate, error: error)
        let importState: SyncState = importSuccessful
            ? .succeeded(started: startDate, ended: endDate)
            : .failed(started: startDate, ended: endDate, error: error)
        let exportState: SyncState = exportSuccessful
            ? .succeeded(started: startDate, ended: endDate)
            : .failed(started: startDate, ended: endDate, error: error)

        self.init(setupState: setupState, importState: importState, exportState: exportState, lastErrorText: errorText, listen: false)
        self.networkAvailable = networkAvailable
        self.iCloudAccountStatus = iCloudAccountStatus
    }
}
