//
//  SyncMonitor.swift
//  
//
//  Created by Grant Grueninger on 9/23/20.
//

import Foundation

@Observable @MainActor
public final class SyncMonitor: Sendable {
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
    init(networkMonitor: NetworkMonitor, ckStateObserver: CloudKitStateObserver) {
        self.networkMonitor = networkMonitor
        self.ckStateObserver = ckStateObserver
    }

    /// Leads to compiler warnings/ issues when using the created manager instances as default variables
    convenience init() {
        self.init(
            networkMonitor: NetworkManager(),
            ckStateObserver: CloudKitStateManager()
        )
    }

    /// - Important: Consider calling this on the `shared` object before creating the CloudKit container. Otherwise cloudState notifications for type `.setup` might be missing
    public func startStateObservation() {
        networkMonitor.startObserving()
        ckAccountManager.startObserving()
        ckStateObserver.observeSyncStates()
    }
}
