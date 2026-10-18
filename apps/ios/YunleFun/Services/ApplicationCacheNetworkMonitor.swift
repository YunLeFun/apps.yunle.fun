import Foundation
import Network

struct ApplicationCacheNetwork: Equatable, Sendable {
    var connected = false
    var wifi = false
    var expensive = false
    var constrained = false

    func permitsAutomaticDownload(wifiOnly: Bool) -> Bool {
        connected && !constrained && (!wifiOnly || (wifi && !expensive))
    }
}

@MainActor
protocol ApplicationCacheNetworkMonitoring: AnyObject {
    func start(_ changed: @escaping @MainActor (ApplicationCacheNetwork) -> Void)
    func stop()
}

@MainActor
final class ApplicationCacheNetworkMonitor: ApplicationCacheNetworkMonitoring {
    private var monitor: NWPathMonitor?
    private var generation = UUID()

    func start(_ changed: @escaping @MainActor (ApplicationCacheNetwork) -> Void) {
        stop()
        let monitor = NWPathMonitor(), generation = generation
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let state = ApplicationCacheNetwork(connected: path.status == .satisfied,
                                                wifi: path.usesInterfaceType(.wifi),
                                                expensive: path.isExpensive, constrained: path.isConstrained)
            Task { @MainActor [weak self] in
                guard self?.generation == generation else { return }
                changed(state)
            }
        }
        monitor.start(queue: DispatchQueue(label: "fun.yunle.cache.network"))
    }

    func stop() {
        generation = UUID()
        monitor?.cancel(); monitor = nil
    }

    deinit { monitor?.cancel() }
}
