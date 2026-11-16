import Foundation

public actor PlaybackURLCache {
    public struct Key: Hashable, Sendable {
        public let musicID: String
        public let quality: Quality

        public init(track: Track, quality: Quality) {
            musicID = "\(track.source.rawValue)_\(track.songmid)"
            self.quality = quality
        }

        public init(musicID: String, quality: Quality) {
            self.musicID = musicID
            self.quality = quality
        }
    }

    private struct Entry: Sendable {
        let url: URL
        let actualQuality: Quality
        let expiresAt: Date
    }

    private var entries: [Key: Entry] = [:]
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    public init(ttl: TimeInterval = 20 * 60, now: @escaping @Sendable () -> Date = { Date() }) {
        self.ttl = ttl
        self.now = now
    }

    public func value(for key: Key) -> URL? {
        resolvedValue(for: key)?.url
    }

    public func resolvedValue(for key: Key) -> ResolvedPlaybackURL? {
        guard let entry = entries[key] else { return nil }
        guard entry.expiresAt > now(), entry.actualQuality.rank >= key.quality.rank else {
            entries[key] = nil
            return nil
        }
        return ResolvedPlaybackURL(url: entry.url, quality: entry.actualQuality)
    }

    public func insert(_ url: URL, actualQuality: Quality, for key: Key) {
        if actualQuality.rank >= key.quality.rank {
            entries[key] = Entry(url: url, actualQuality: actualQuality, expiresAt: now().addingTimeInterval(ttl))
        }
        let actualKey = Key(musicID: key.musicID, quality: actualQuality)
        entries[actualKey] = Entry(url: url, actualQuality: actualQuality, expiresAt: now().addingTimeInterval(ttl))
    }

    public func removeValue(for key: Key) {
        entries[key] = nil
    }

    public func removeAll() {
        entries.removeAll()
    }
}

/// 缓存完整音质回退链的最终结果，供播放、下一首准备和整首缓存共同复用。
/// 这里允许记录已成功回退的实际档位；底层单档 URL 缓存仍要求不低于请求音质。
public actor CachedPlaybackURLResolver: PlaybackURLRefreshing {
    private struct Entry {
        let result: ResolvedPlaybackURL
        let expiresAt: Date
    }

    private struct RequestKey: Hashable {
        let cacheKey: PlaybackURLCache.Key
        let refreshing: Bool
    }

    private struct Pending {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<ResolvedPlaybackURL, Error>]
    }

    private nonisolated let resolver: PlaybackURLResolving
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private var entries: [PlaybackURLCache.Key: Entry] = [:]
    private var pending: [RequestKey: Pending] = [:]
    private var latestRequests: [PlaybackURLCache.Key: UUID] = [:]

    public init(
        resolver: PlaybackURLResolving,
        ttl: TimeInterval = 20 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.resolver = resolver
        self.ttl = ttl
        self.now = now
    }

    public nonisolated func supportsPlayback(of source: MusicSource) -> Bool {
        resolver.supportsPlayback(of: source)
    }

    public func musicURL(for track: Track, quality: Quality) async throws -> URL {
        try await resolvedMusicURL(for: track, quality: quality, refreshing: false).url
    }

    public func refreshMusicURL(for track: Track, quality: Quality) async throws -> URL {
        try await resolvedMusicURL(for: track, quality: quality, refreshing: true).url
    }

    public func resolvedMusicURL(for track: Track, quality: Quality, refreshing: Bool) async throws -> ResolvedPlaybackURL {
        try Task.checkCancellation()
        try resolver.requirePlaybackSupport(for: track.source)
        if track.source == .local {
            return try await resolver.resolvedMusicURL(for: track, quality: quality, refreshing: refreshing)
        }
        let cacheKey = PlaybackURLCache.Key(track: track, quality: quality)
        if refreshing {
            entries[cacheKey] = nil
        } else if let entry = entries[cacheKey], entry.expiresAt > now() {
            return entry.result
        }
        // 刷新进行中时，新消费者等待刷新结果，不能再加入已过期的旧解析。
        let refreshKey = RequestKey(cacheKey: cacheKey, refreshing: true)
        let key = pending[refreshKey] != nil ? refreshKey : RequestKey(cacheKey: cacheKey, refreshing: refreshing)
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            let result: ResolvedPlaybackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ResolvedPlaybackURL, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if var request = pending[key] {
                    request.waiters[waiterID] = continuation
                    pending[key] = request
                    return
                }
                let id = UUID()
                let task = Task { [resolver] in
                    let result: Result<ResolvedPlaybackURL, Error>
                    do {
                        result = .success(try await resolver.resolvedMusicURL(
                            for: track, quality: quality, refreshing: refreshing
                        ))
                    } catch {
                        result = .failure(error)
                    }
                    finish(key, id: id, result: result)
                }
                latestRequests[cacheKey] = id
                pending[key] = Pending(id: id, task: task, waiters: [waiterID: continuation])
            }
            try Task.checkCancellation()
            return result
        } onCancel: {
            Task { await self.cancelWaiter(waiterID, for: key) }
        }
    }

    private func finish(_ key: RequestKey, id: UUID, result: Result<ResolvedPlaybackURL, Error>) {
        guard let request = pending[key], request.id == id else { return }
        pending[key] = nil
        if latestRequests[key.cacheKey] == id {
            latestRequests[key.cacheKey] = nil
            if case let .success(resolved) = result {
                let date = now()
                entries = entries.filter { $0.value.expiresAt > date }
                entries[key.cacheKey] = Entry(result: resolved, expiresAt: date.addingTimeInterval(ttl))
            }
        }
        for waiter in request.waiters.values { waiter.resume(with: result) }
    }

    private func cancelWaiter(_ id: UUID, for key: RequestKey) {
        guard var request = pending[key], let waiter = request.waiters.removeValue(forKey: id) else { return }
        if request.waiters.isEmpty {
            pending[key] = nil
            if latestRequests[key.cacheKey] == request.id { latestRequests[key.cacheKey] = nil }
            request.task.cancel()
        } else {
            pending[key] = request
        }
        waiter.resume(throwing: CancellationError())
    }
}

extension Quality {
    var rank: Int {
        switch self {
        case .standard: 0
        case .high: 1
        case .lossless: 2
        case .hiRes: 3
        case .master: 4
        }
    }
}
