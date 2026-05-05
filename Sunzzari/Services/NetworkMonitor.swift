import Foundation
import Network

/// Lightweight wrapper around NWPathMonitor so views can decide whether to
/// kick off bandwidth-heavy work (e.g. story image prefetch). The monitor
/// runs once per process and updates flags on a background queue; reads
/// from any thread are safe because Swift handles atomic Bool/enum loads.
///
/// Use `isUnconstrained` as the gate for prefetch / preload-all behavior.
/// On cellular, Low Data Mode, or a hotspot the prefetch skips and we
/// fall back to fetch-on-demand inside AsyncImage.
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "sunzzari.network-monitor")

    private(set) var isExpensive: Bool = false
    private(set) var isConstrained: Bool = false
    private(set) var isCellular: Bool = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.isExpensive = path.isExpensive
            self.isConstrained = path.isConstrained
            self.isCellular = path.usesInterfaceType(.cellular)
        }
        monitor.start(queue: queue)
    }

    /// True when we can afford to prefetch images aggressively (Wi-Fi or
    /// wired, no Low Data Mode). Treats unknown state as expensive — better
    /// to under-prefetch than to drain a tester's data plan during the
    /// Mother's Day reveal week.
    var isUnconstrained: Bool {
        !isExpensive && !isConstrained && !isCellular
    }
}
