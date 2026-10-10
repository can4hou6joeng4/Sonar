import Foundation

enum PlaybackResolverPipeline {
    static func make(primary: PlaybackURLResolving) -> PlaybackURLResolving {
        HighestAvailableQualityPlaybackURLResolver(resolver: primary)
    }
}

public final class HighestAvailableQualityPlaybackURLResolver: PlaybackURLRefreshing, @unchecked Sendable {
    private static let qualityOrder = Quality.descendingOrder

    private let resolver: PlaybackURLResolving

    public init(resolver: PlaybackURLResolving) {
        self.resolver = resolver
    }

    public func musicURL(for track: Track, quality: Quality) async throws -> URL {
        try await resolve(track: track, quality: quality, refreshing: false)
    }

    public func refreshMusicURL(for track: Track, quality: Quality) async throws -> URL {
        try await resolve(track: track, quality: quality, refreshing: true)
    }

    private func resolve(track: Track, quality: Quality, refreshing: Bool) async throws -> URL {
        try track.source.requireEnabled()
        guard let startingIndex = Self.qualityOrder.firstIndex(of: quality) else {
            return try await resolveCandidate(track: track, quality: quality, refreshing: refreshing)
        }

        var eligibleFailures: [SourceError] = []
        for candidate in Self.qualityOrder[startingIndex...] {
            try Task.checkCancellation()
            do {
                return try await resolveCandidate(track: track, quality: candidate, refreshing: refreshing)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as SourceError {
                switch error {
                case .network:
                    throw error
                case .credentialRequired:
                    throw error
                case let .source(message):
                    guard PlaybackFallbackPolicy.allowsFallback(for: message) else { throw error }
                    eligibleFailures.append(error)
                }
            }
        }

        if let terminalError = eligibleFailures.last {
            throw terminalError
        }
        throw SourceError.source(message: "没有可用的播放音质")
    }

    private func resolveCandidate(track: Track, quality: Quality, refreshing: Bool) async throws -> URL {
        if refreshing, let refreshable = resolver as? PlaybackURLRefreshing {
            return try await refreshable.refreshMusicURL(for: track, quality: quality)
        }
        return try await resolver.musicURL(for: track, quality: quality)
    }

}

enum PlaybackFallbackPolicy {
    /// `SourceError.source` intentionally keeps the public three-way error contract.
    /// Be conservative here: only known entitlement and quality failures may retry.
    static func allowsFallback(for message: String) -> Bool {
        let normalized = message.lowercased()
        if normalized.contains("音质不可用") { return true }
        if normalized.contains("不支持") && (normalized.contains("音质") || normalized.contains("hi-res") || normalized.contains("hires")) {
            return true
        }
        return [
            "无版权",
            "需要会员",
            "无法获取无损",
            "仅返回试听片段",
            "加载获取歌曲失败",
            "未返回可用链接",
            "未能匹配可用链接",
        ].contains { normalized.contains($0) }
    }

    static func allowsQualityFallback(for error: SourceError) -> Bool {
        switch error {
        case .network:
            return false
        case .credentialRequired:
            return false
        case let .source(message):
            return allowsFallback(for: message)
        }
    }
}
