import AVFoundation
import Foundation

extension Notification.Name {
    static let sonarAudioCacheDownloadsDidChange = Notification.Name("sonar.audioCache.downloadsDidChange")
}

/// 控制器同步失效旧批次，尚未进入下载 actor 的调用也不能重新注册任务。
final class AudioCacheRequestToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// 整首下载与播放流独立；系统会话和请求都禁止蜂窝、计费及低数据模式。
actor AudioCacheDownloader {
    typealias Download = @Sendable (URLRequest) async throws -> (URL, URLResponse)

    private struct Job: Sendable {
        let id = UUID()
        let track: Track
        let quality: Quality
        let generation: Int
        let permission: AudioCacheRequestToken?

        var key: String { "\(track.musicID)|\(quality.rawValue)" }
    }

    private struct Active {
        let job: Job
        let task: Task<Void, Never>
    }

    enum DownloadError: Error, Sendable {
        case invalidResponse
        case nonMedia
        case incompleteFile
        case noSpace
    }

    private let store: AudioCacheStore
    private let resolver: PlaybackURLResolving
    private let download: Download
    private let maxConcurrent: Int
    private let allowsDownloads: @Sendable () -> Bool

    private var queue: [Job] = []
    private var active: [UUID: Active] = [:]
    private var pending: [String: UUID] = [:]
    private var interrupted: Set<UUID> = []
    private var suspended = false
    private var waitingForNetwork = false
    private var spaceBlocked = false
    private var generation = 0
    private var retryTask: Task<Void, Never>?
    private var lastError: String?

    init(
        store: AudioCacheStore,
        resolver: PlaybackURLResolving,
        maxConcurrent: Int = 2,
        isExpensive: @escaping @Sendable () -> Bool,
        allowsDownloads: (@Sendable () -> Bool)? = nil,
        download: Download? = nil
    ) {
        self.store = store
        self.resolver = resolver
        self.maxConcurrent = min(2, max(1, maxConcurrent))
        self.allowsDownloads = { !isExpensive() && (allowsDownloads?() ?? true) }

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.allowsCellularAccess = false
        configuration.allowsExpensiveNetworkAccess = false
        configuration.allowsConstrainedNetworkAccess = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpMaximumConnectionsPerHost = self.maxConcurrent
        let session = URLSession(configuration: configuration)
        self.download = download ?? { request in try await session.download(for: request) }
    }

    func enqueue(
        track: Track, quality: Quality, priorityFirst: Bool,
        permission: AudioCacheRequestToken? = nil
    ) {
        guard track.source != .local, track.source.isEnabled, permission?.isCancelled != true else { return }
        // 网络已恢复但恢复通知尚未到达时，新的显式提交也可继续已有队列。
        if allowsDownloads() {
            suspended = false
            waitingForNetwork = false
            spaceBlocked = false
        }
        let key = "\(track.musicID)|\(quality.rawValue)"
        if let id = pending[key] {
            if priorityFirst, let index = queue.firstIndex(where: { $0.id == id }) {
                queue.insert(queue.remove(at: index), at: 0)
            }
            // 显式再次提交也允许重新检查空间或网络；不会新建相同任务。
            spaceBlocked = false
            waitingForNetwork = false
            pump()
            return
        }
        let job = Job(track: track, quality: quality, generation: generation, permission: permission)
        // 注册与入队没有 await，后续查索引、解析和下载均已受任务身份保护。
        pending[key] = job.id
        if priorityFirst { queue.insert(job, at: 0) } else { queue.append(job) }
        spaceBlocked = false
        pump()
    }

    func suspendForExpensiveNetwork() {
        suspended = true
        retryTask?.cancel()
        retryTask = nil
        for value in active.values {
            interrupted.insert(value.job.id)
            value.task.cancel()
        }
        postDownloadsChanged()
    }

    func resume() {
        suspended = false
        waitingForNetwork = false
        spaceBlocked = false
        retryTask?.cancel()
        retryTask = nil
        pump()
    }

    func cancelAll() {
        generation += 1
        queue.removeAll()
        pending.removeAll()
        interrupted.removeAll()
        waitingForNetwork = false
        spaceBlocked = false
        lastError = nil
        retryTask?.cancel()
        retryTask = nil
        for value in active.values { value.task.cancel() }
        // 被取消的任务仍占槽位，退出后按 UUID 清理，不能删除新代任务。
        postDownloadsChanged()
    }

    func activeCount() -> Int { active.count }

    func lastErrorMessage() -> String? { lastError }

    // MARK: - 调度

    private func pump() {
        guard !suspended, !waitingForNetwork, !spaceBlocked, allowsDownloads() else {
            postDownloadsChanged()
            return
        }
        queue.removeAll { job in
            guard !isCurrent(job) else { return false }
            if pending[job.key] == job.id { pending[job.key] = nil }
            return true
        }
        while active.count < maxConcurrent {
            // 同一首不同请求档位串行处理，后一个任务能复用前一个的实际音质文件。
            let busyTracks = Set(active.values.map { $0.job.track.musicID })
            guard let index = queue.firstIndex(where: { !busyTracks.contains($0.track.musicID) }) else { break }
            let job = queue.remove(at: index)
            let task = Task<Void, Never> { [weak self] in
                guard let self else { return }
                await self.run(job)
            }
            active[job.id] = Active(job: job, task: task)
        }
        postDownloadsChanged()
    }

    private func run(_ job: Job) async {
        var requeue = false
        defer {
            active[job.id] = nil
            interrupted.remove(job.id)
            if requeue, isCurrent(job) {
                queue.insert(job, at: 0)
            } else if pending[job.key] == job.id {
                pending[job.key] = nil
            }
            pump()
        }
        guard isCurrent(job) else { return }
        guard !suspended, allowsDownloads() else {
            requeue = true
            return
        }

        for attempt in 0..<2 {
            do {
                try check(job)
                if await store.cachedEntry(for: job.track, preferred: job.quality, allowLowerQuality: false) != nil {
                    try check(job)
                    return
                }
                try check(job)
                guard await store.hasSpaceForDownload() else { throw DownloadError.noSpace }
                try check(job)
                let resolved = try await resolver.resolvedMusicURL(
                    for: job.track, quality: job.quality, refreshing: attempt > 0
                )
                try check(job)
                if let cached = await store.cachedEntry(
                    for: job.track, preferred: resolved.quality, allowLowerQuality: false
                ) {
                    try check(job)
                    if try await store.rememberRequest(job.quality, for: cached) {
                        try check(job)
                        return
                    }
                }
                try check(job)
                guard await store.hasSpaceForDownload() else { throw DownloadError.noSpace }
                try check(job)
                var request = URLRequest(url: resolved.url)
                request.httpMethod = "GET"
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 60
                request.allowsCellularAccess = false
                request.allowsExpensiveNetworkAccess = false
                request.allowsConstrainedNetworkAccess = false
                let (tempURL, response) = try await download(request)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                try check(job)
                try Self.validateResponse(response, fileURL: tempURL)
                let ext = Self.fileExtension(mimeType: response.mimeType, url: resolved.url, quality: resolved.quality)
                // AVFoundation 依赖文件扩展名识别本地容器，下载临时文件先改成真实媒体后缀。
                let namedURL = tempURL.deletingLastPathComponent()
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                try FileManager.default.moveItem(at: tempURL, to: namedURL)
                defer { try? FileManager.default.removeItem(at: namedURL) }
                try await Self.validateAudioFile(at: namedURL, expectedDuration: job.track.durationSeconds)
                try check(job)
                _ = try await store.install(
                    tempURL: namedURL, track: job.track, actualQuality: resolved.quality,
                    fileExtension: ext, requestedQuality: job.quality
                )
                if !spaceBlocked, !waitingForNetwork { lastError = nil }
                postDownloadsChanged()
                return
            } catch {
                guard isCurrent(job) else { return }
                if Task.isCancelled || error is CancellationError {
                    // 即使已经快速恢复 Wi-Fi，被网络暂停打断的任务仍需重新排队。
                    requeue = interrupted.contains(job.id) || suspended || !allowsDownloads()
                    return
                }
                if suspended || !allowsDownloads() {
                    requeue = true
                    return
                }
                if Self.isOutOfSpace(error) {
                    lastError = "设备可用空间不足，已停止新增缓存，已有缓存保留"
                    spaceBlocked = true
                    requeue = true
                    postDownloadsChanged()
                    return
                }
                if attempt == 1 {
                    if Self.isNetworkError(error) {
                        lastError = "缓存下载等待网络恢复：\(job.track.title)"
                        waitingForNetwork = true
                        requeue = true
                        scheduleNetworkRetry()
                    } else {
                        lastError = "缓存下载失败：\(job.track.title)"
                    }
                    postDownloadsChanged()
                    return
                }
                do { try await Task.sleep(for: .seconds(1)) } catch {
                    requeue = isCurrent(job) && (interrupted.contains(job.id) || suspended || !allowsDownloads())
                    return
                }
            }
        }
    }

    private func isCurrent(_ job: Job) -> Bool {
        job.generation == generation && job.permission?.isCancelled != true
    }

    private func check(_ job: Job) throws {
        try Task.checkCancellation()
        guard isCurrent(job), !suspended, allowsDownloads() else { throw CancellationError() }
    }

    private func scheduleNetworkRetry() {
        guard retryTask == nil else { return }
        let currentGeneration = generation
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            await self?.retryNetworkJobs(generation: currentGeneration)
        }
    }

    private func retryNetworkJobs(generation expected: Int) {
        guard expected == generation else { return }
        retryTask = nil
        waitingForNetwork = false
        pump()
    }

    private func postDownloadsChanged() {
        NotificationCenter.default.post(name: .sonarAudioCacheDownloadsDidChange, object: nil)
    }

    // MARK: - 完整文件校验

    static func validateResponse(_ response: URLResponse, fileURL: URL) throws {
        guard let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode) else {
            throw DownloadError.invalidResponse
        }
        let mime = (http.mimeType ?? "").lowercased()
        guard !mime.hasPrefix("text/"), !mime.contains("json"), !mime.contains("html"),
              !mime.contains("xml"), !mime.contains("mpegurl") else { throw DownloadError.nonMedia }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0 else {
            throw DownloadError.incompleteFile
        }
        if let range = http.value(forHTTPHeaderField: "Content-Range") {
            let parts = range.lowercased().split(separator: " ")
            guard parts.count == 2, parts[0] == "bytes" else { throw DownloadError.incompleteFile }
            let extent = parts[1].split(separator: "/")
            let bounds = extent.first?.split(separator: "-") ?? []
            guard extent.count == 2, bounds.count == 2, Int64(bounds[0]) == 0,
                  let end = Int64(bounds[1]), let total = Int64(extent[1]), total > 0,
                  end == total - 1, size == total else { throw DownloadError.incompleteFile }
        } else if http.statusCode == 206 {
            throw DownloadError.incompleteFile
        }
        let encoding = http.value(forHTTPHeaderField: "Content-Encoding")?.lowercased() ?? "identity"
        if encoding == "identity", response.expectedContentLength > 0, size != response.expectedContentLength {
            throw DownloadError.incompleteFile
        }
    }

    private static func validateAudioFile(at url: URL, expectedDuration: TimeInterval?) async throws {
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true] as [String: Any]
        )
        guard try await asset.load(.isPlayable) else { throw DownloadError.nonMedia }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds
        guard !audioTracks.isEmpty, duration.isFinite, duration > 0 else { throw DownloadError.nonMedia }
        if let expectedDuration, expectedDuration > 0 {
            let tolerance = max(3, expectedDuration * 0.02)
            guard duration + tolerance >= expectedDuration else { throw DownloadError.incompleteFile }
        }
    }

    private static func isOutOfSpace(_ error: Error) -> Bool {
        if case DownloadError.noSpace = error { return true }
        let cause = error as NSError
        if cause.domain == NSCocoaErrorDomain, cause.code == NSFileWriteOutOfSpaceError { return true }
        if cause.domain == NSPOSIXErrorDomain, cause.code == 28 { return true }
        if let underlying = cause.userInfo[NSUnderlyingErrorKey] as? Error { return isOutOfSpace(underlying) }
        return false
    }

    private static func isNetworkError(_ error: Error) -> Bool {
        if case SourceError.network = error { return true }
        guard let urlError = error as? URLError else { return false }
        return [
            .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
            .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff
        ].contains(urlError.code)
    }

    private static func fileExtension(mimeType: String?, url: URL, quality: Quality) -> String {
        switch (mimeType ?? "").lowercased() {
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/mp4", "audio/x-m4a": return "m4a"
        case "audio/aac": return "aac"
        case "audio/wav", "audio/x-wav": return "wav"
        case "audio/ogg": return "ogg"
        default: break
        }
        let ext = url.pathExtension.lowercased()
        if ["mp3", "flac", "m4a", "aac", "wav", "ogg"].contains(ext) { return ext }
        return quality == .standard || quality == .high ? "mp3" : "flac"
    }
}
