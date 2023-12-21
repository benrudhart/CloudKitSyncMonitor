import Foundation
import CloudKit

@Observable
final class CKAccountManager {
    /// The current status of the user's iCloud account - updated automatically if they change it
    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine

    init() {
        Task {
            accountStatus = await CKContainer.default().fetchAccountStatus()
        }
    }

    func startObserving() {
        Task { [weak self] in
            await self?.setupAccountStateListener()
        }
    }

    /// Monitor changes to the iCloud account (e.g. login/logout)
    @MainActor
    private func setupAccountStateListener() async  {
        let accountStatusStream = NotificationCenter.default
            .notifications(named: .CKAccountChanged)
            .map { _ in await CKContainer.default().fetchAccountStatus() }

        for await accountStatus in accountStatusStream {
            self.accountStatus = accountStatus
        }
    }
}

private extension CKContainer {
    func fetchAccountStatus() async -> CKAccountStatus {
        do {
            return try await accountStatus()
        } catch {
            return .couldNotDetermine // ignore the error
        }
    }
}
