import Foundation
import Network

@MainActor
protocol NetworkMonitor: Sendable {
    var isNetworkAvailable: Bool { get }
    func startObserving()
}
