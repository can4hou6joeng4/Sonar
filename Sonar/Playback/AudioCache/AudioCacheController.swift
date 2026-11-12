import Foundation
import Observation

/// 播放服务与设置页共享的缓存入口，批次取消不会修改歌单或音质偏好。
@MainActor
@Observable
final class AudioCacheController: PlaybackAudioCaching {
    private static let autoCacheKey = "sonar.audioCache.autoCacheEnabled"
    private static let cellularOnlyKey = "sonar.audioCache.cellularOnlyCached"

    private(set) var totalBytes: Int64 = 0
    private(set) var cachedCount = 0
    private(set) var activeDownloads = 0
    private(set) var lastError: String?

    var autoCacheEnabled: Bool {
        didSet {
            defaults.set(autoCacheEnabled, forKey: Self.autoCacheKey)
            guard oldValue != autoCacheEnabled else { return }
            replaceRequestToken()
            // 新开启的批次也等待此前关闭/清空完成，旧取消不能杀掉新任务。
            let previous = mutationTask
            let downloader = self.downloader
            mutationTask = Task {
                await previous?.value
                await downloader.cancelAll()
            }
            NotificationCenter.default.post(name: .sonarPlaybackDataPolicyDidChange, object: nil)
            scheduleRefresh()
        }
    }

    var cellularOnlyCached: Bool {
        didSet {
            defaults.set(cellularOnlyCached, forKey: Self.cellularOnlyKey)
            NotificationCenter.default.post(name: .sonarPlaybackDataPolicyDidChange, object: nil)
        }
    }

    private let store: AudioCacheStore
    private let downloader: AudioCacheDownloader
    private let network: NetworkStatusMonitor
    private let defaults: UserDefaults
    private var observers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    private var scheduledRefreshTask: Task<Void, Never>?
    private var mutationTask: Task<Void, Never>?
    private var requestToken = AudioCacheRequestToken()
    private var clearingCount = 0
    private var cacheRevision = 0

    init(
        store: AudioCacheStore,
        downloader: AudioCacheDownloader,
        network: NetworkStatusMonitor,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.downloader = downloader
        self.network = network
        self.defaults = defaults
        self.autoCacheEnabled = defaults.object(forKey: Self.autoCacheKey) as? Bool ?? true
        self.cellularOnlyCached = defaults.object(forKey: Self.cellularOnlyKey) as? Bool ?? true
        if !autoCacheEnabled { requestToken.cancel() }
        installObservers()
        refreshStats()
    }

    deinit {
        MainActor.assumeIsolated {
            requestToken.cancel()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            refreshTask?.cancel()
            scheduledRefreshTask?.cancel()
        }
    }

    // MARK: - PlaybackAudioCaching

    func cachedURL(for track: Track, preferred: Quality, allowLowerQuality: Bool) async -> (url: URL, quality: Quality)? {
        guard clearingCount == 0 else { return nil }
        let revision = cacheRevision
        let result = await store.cachedURL(for: track, preferred: preferred, allowLowerQuality: allowLowerQuality)
        guard revision == cacheRevision, clearingCount == 0 else { return nil }
        return result
    }

    func invalidateCachedAudio(for track: Track, url: URL) async {
        cacheRevision += 1
        do { try await store.invalidate(for: track, url: url) } catch {
            // 存储层保留具体错误，由同一统计刷新入口展示。
        }
        refreshStats()
    }

    func cacheTracks(_ tracks: [Track], quality: Quality, priorityFirst: Bool) async {
        let token = requestToken
        await mutationTask?.value
        guard canEnqueue(token) else { return }
        for (index, track) in tracks.enumerated() {
            guard !Task.isCancelled, canEnqueue(token) else { return }
            await downloader.enqueue(
                track: track, quality: quality, priorityFirst: priorityFirst && index == 0,
                permission: token
            )
        }
        scheduleRefresh()
    }

    func handleNetworkChange(isExpensive: Bool) async {
        await mutationTask?.value
        // 读取当前路径，延迟到达的旧通知不能恢复一个已经断开的网络。
        if autoCacheEnabled, clearingCount == 0, network.allowsDownloads {
            await downloader.resume()
        } else {
            await downloader.suspendForExpensiveNetwork()
        }
        scheduleRefresh()
    }

    // MARK: - 设置页展示

    var usageText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: totalBytes)) · \(cachedCount) 首"
    }

    var networkDescription: String {
        guard network.isConnected else { return "未联网" }
        if network.interfaceName == "cellular" { return "蜂窝网络" }
        if network.isExpensive { return "按流量计费网络" }
        if network.isConstrained { return "低数据模式" }
        return network.interfaceName == "wired" ? "有线网络" : "Wi-Fi"
    }

    var downloadsText: String {
        if let lastError, activeDownloads == 0 { return lastError }
        if activeDownloads > 0 { return "正在缓存 \(activeDownloads) 首" }
        return "Wi-Fi 下自动缓存正在播放与后续歌曲"
    }

    func clearCache() async {
        clearingCount += 1
        cacheRevision += 1
        replaceRequestToken()
        let previous = mutationTask
        let downloader = self.downloader
        let store = self.store
        let operation = Task {
            await previous?.value
            await downloader.cancelAll()
            do { try await store.clear() } catch {
                // 清空失败由存储层报告；已有文件继续计入占用。
            }
        }
        mutationTask = operation
        await operation.value
        clearingCount -= 1
        if clearingCount == 0 {
            replaceRequestToken()
            if autoCacheEnabled, network.allowsDownloads { await downloader.resume() }
        }
        refreshStats()
    }

    func refreshStats() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let bytes = await self.store.totalBytes()
            let count = await self.store.count()
            let active = await self.downloader.activeCount()
            let downloadError = await self.downloader.lastErrorMessage()
            let storageError = await self.store.lastErrorMessage()
            guard !Task.isCancelled else { return }
            self.totalBytes = bytes
            self.cachedCount = count
            self.activeDownloads = active
            self.lastError = storageError ?? downloadError
        }
    }

    private func canEnqueue(_ token: AudioCacheRequestToken) -> Bool {
        token === requestToken && !token.isCancelled && autoCacheEnabled && clearingCount == 0 && network.allowsDownloads
    }

    private func replaceRequestToken() {
        requestToken.cancel()
        requestToken = AudioCacheRequestToken()
        if !autoCacheEnabled || clearingCount > 0 { requestToken.cancel() }
    }

    private func scheduleRefresh() {
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            self?.refreshStats()
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        for name in [Notification.Name.sonarAudioCacheDidChange, .sonarAudioCacheDownloadsDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshStats() }
            })
        }
    }
}
