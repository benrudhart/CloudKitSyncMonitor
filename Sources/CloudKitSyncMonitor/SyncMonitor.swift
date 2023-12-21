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

        return ckStateObserver.syncStateSummary
    }

    public let ckStateObserver: CloudKitStateObserver
    let networkMonitor: NetworkMonitor
    let ckAccountManager = CKAccountManager()

    // MARK: - Initializers

    /// Creates a new sync monitor
    init(networkMonitor: NetworkMonitor = NetworkManager(),
         ckStateObserver: CloudKitStateObserver = CloudKitStateManager()) {
        self.networkMonitor = networkMonitor
        self.ckStateObserver = ckStateObserver
    }

    /// - Important: Consider calling this on the `shared` object before creating the CloudKit container. Otherwise cloudState notifications for type `.setup` might be missing
    public func startStateObservation() {
        networkMonitor.startObserving()
        ckAccountManager.startObserving()
        ckStateObserver.observeSyncStates()
    }
}
