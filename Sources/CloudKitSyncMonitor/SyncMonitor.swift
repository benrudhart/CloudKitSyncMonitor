//
//  SyncMonitor.swift
//  
//
//  Created by Grant Grueninger on 9/23/20.
//

import Foundation

@Observable
public final class SyncMonitor {
    public static let shared = SyncMonitor()

    public var syncStateSummary: SyncSummaryStatus {
        if networkMonitor.isNetworkAvailable == false {
            return .noNetwork
        }

        if ckAccountManager.accountStatus != .available {
            return .accountNotAvailable
        }

        return cloudStateManager.syncStateSummary
    }

    public let cloudStateManager = CloudStateManager()
    let networkMonitor: NetworkMonitor
    let ckAccountManager = CKAccountManager()

    // MARK: - Initializers

    /// Creates a new sync monitor
    init(networkMonitor: NetworkMonitor = NetworkManager(),
         setupState: SyncState = .notStarted,
         importState: SyncState = .notStarted,
         exportState: SyncState = .notStarted) {
        self.networkMonitor = networkMonitor
    }

    /// - Important: Consider calling this on the `shared` object before creating the CloudKit container. Otherwise cloudState notifications for type `.setup` might be missing
    public func startStateObservation() {
        networkMonitor.startObserving()
        ckAccountManager.startObserving()
        cloudStateManager.observeSyncStates()
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
        self.init(networkMonitor: networkMonitor, setupState: setupState, importState: importState, exportState: exportState)

        struct NetworkMonitorMock: NetworkMonitor {
            var isNetworkAvailable: Bool
            func startObserving() {}
        }
    }
}
