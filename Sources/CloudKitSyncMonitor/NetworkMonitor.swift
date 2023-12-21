import Foundation
import Network

protocol NetworkMonitor {
    var isNetworkAvailable: Bool { get }
    func startObserving()
}
