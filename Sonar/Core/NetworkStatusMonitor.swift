import Foundation
import Network
import Observation

/// 首次路径回调前保持未知、未连接状态；后台下载读取锁保护的完整路径快照。
@MainActor
@Observable
final class NetworkStatusMonitor: PlaybackNetworkStatus {
    private(set) var isExpensive = true
    private(set) var isConnected = false
    private(set) var isConstrained = false
    private(set) var interfaceName = "unknown"

    var allowsDownloads: Bool {
        isConnected && !isExpensive && !isConstrained && ["wifi", "wired"].contains(interfaceName)
    }

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "cn.bobochang.sonar.network-status")
    @ObservationIgnored private let snapshot = NetworkStatusSnapshot()
    @ObservationIgnored private var lastAppliedRevision = 0

    nonisolated var isExpensiveSnapshot: Bool { snapshot.read().status.isExpensive }
    nonisolated var isConnectedSnapshot: Bool { snapshot.read().status.isConnected }
    nonisolated var allowsDownloadsSnapshot: Bool { snapshot.read().status.allowsDownloads }

    init(startMonitoring: Bool = true) {
        guard startMonitoring else { return }
        let snapshot = self.snapshot
        monitor.pathUpdateHandler = { [weak self, snapshot] path in
            let status = NetworkPathStatus(
                isConnected: path.status == .satisfied,
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained,
                interfaceName: Self.interfaceName(for: path)
            )
            let value = snapshot.update(status)
            Task { @MainActor [weak self] in self?.apply(value) }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }

    /// 与路径回调共用的状态入口，也可由本地测试注入确定的连接变化。
    func updateStatus(
        isConnected: Bool, isExpensive: Bool, interfaceName: String, isConstrained: Bool = false
    ) {
        apply(snapshot.update(NetworkPathStatus(
            isConnected: isConnected, isExpensive: isExpensive,
            isConstrained: isConstrained, interfaceName: interfaceName
        )))
    }

    private func apply(_ value: VersionedNetworkPathStatus) {
        guard value.revision > lastAppliedRevision else { return }
        lastAppliedRevision = value.revision
        let status = value.status
        let changed = isConnected != status.isConnected || isExpensive != status.isExpensive
            || interfaceName != status.interfaceName || isConstrained != status.isConstrained
        isConnected = status.isConnected
        isExpensive = status.isExpensive
        isConstrained = status.isConstrained
        interfaceName = status.interfaceName
        if changed {
            NotificationCenter.default.post(name: .sonarNetworkStatusDidChange, object: nil)
        }
    }

    nonisolated private static func interfaceName(for path: NWPath) -> String {
        if path.usesInterfaceType(.cellular) { return "cellular" }
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.wiredEthernet) { return "wired" }
        return "other"
    }
}

private struct NetworkPathStatus: Sendable {
    var isConnected = false
    var isExpensive = true
    var isConstrained = false
    var interfaceName = "unknown"

    var allowsDownloads: Bool {
        isConnected && !isExpensive && !isConstrained && ["wifi", "wired"].contains(interfaceName)
    }
}

private struct VersionedNetworkPathStatus: Sendable {
    var status = NetworkPathStatus()
    var revision = 0
}

/// 只保存完整路径快照，读写都在锁内完成。
private final class NetworkStatusSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var value = VersionedNetworkPathStatus()

    func update(_ status: NetworkPathStatus) -> VersionedNetworkPathStatus {
        lock.lock()
        defer { lock.unlock() }
        value.status = status
        value.revision += 1
        return value
    }

    func read() -> VersionedNetworkPathStatus {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
