import Foundation
import Network
import Observation
import os.log

/// Single source of truth for connectivity. Drives the offline banner and, on
/// every offline -> online transition, kicks the sync coordinator to flush the
/// pending-mutation queue and any deferred photo verifications.
///
/// `isOnline` starts optimistically true so a warm launch never flashes the
/// offline banner before the first path callback arrives; the monitor corrects
/// it within milliseconds if we are actually offline.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.reinspire.networkmonitor")
    private let logger = Logger(subsystem: "com.reinspire", category: "NetworkMonitor")
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let wasOnline = self.isOnline
                self.isOnline = online
                if online && !wasOnline {
                    self.logger.debug("network back online -- draining offline queues")
                    await SyncService.shared.syncNow()
                }
            }
        }
        monitor.start(queue: queue)
    }
}
