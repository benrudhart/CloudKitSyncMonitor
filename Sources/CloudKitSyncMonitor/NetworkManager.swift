import Foundation
import Network

@Observable
final class NetworkManager: NetworkMonitor {
    /// Network path monitor that's used to track whether we can reach the network at all
    private let monitor = NWPathMonitor()

    /// The queue on which we'll run our network monitor
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")

    private(set) var isNetworkAvailable: Bool

    init() {
        self.isNetworkAvailable = monitor.currentPath.isNetworkAvailable
    }

    /// Update the network status when the OS reports a change. Note that we ignore whether the connection is
    /// expensive or not - we just care whether iCloud is _able_ to sync. If there's no network,
    /// NSPersistentCloudKitContainer will try to sync but report an error. We consider that a real error unless
    /// the network is not available at all. If it's available but expensive, it's still an error.
    /// Ostensively, if the user's device has iCloud syncing turned off (e.g. due to low power mode or not
    /// allowing syncing over cellular connections), NSPersistentCloudKitContainer won't try to sync.
    /// If that assumption is incorrect, we'll need to update the logic in this class.
    func startObserving() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async { [weak self] in
                self?.isNetworkAvailable = path.isNetworkAvailable
            }
        }

        monitor.start(queue: monitorQueue)
    }
}

extension NWPath {
    var isNetworkAvailable: Bool {
#if os(watchOS)
        return availableInterfaces.count > 0
#else
        return status == .satisfied
#endif
    }
}
