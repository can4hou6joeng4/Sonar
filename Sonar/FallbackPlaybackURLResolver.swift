import Foundation

enum PlaybackResolverPipeline {
    static func make(
        primary: PlaybackURLResolving,
        sourceRuntime: SourceRuntime,
        publicFallback: PlaybackURLResolving? = PublicStreamPlaybackURLResolver()
    ) -> PlaybackURLResolving {
        FallbackPlaybackURLResolver(
            primary: HighestAvailableQualityPlaybackURLResolver(resolver: primary),
            sourceRuntime: sourceRuntime,
            publicFallback: publicFallback
        )
    }
}

public final class HighestAvailableQualityPlaybackURLResolver: PlaybackURLRefreshing, @unchecked Sendable {
    private static let qualityOrder: [Quality] = [.hiRes, .lossless, .high, .standard]

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
                    eligibleFailures.append(error)
                case let .source(message):
                    guard PlaybackFallbackPolicy.allowsFallback(for: message) else { throw error }
                    eligibleFailures.append(error)
                }
            }
        }

        if let credentialError = eligibleFailures.last(where: {
            if case .credentialRequired = $0 { return true }
            return false
        }) {
            throw credentialError
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
        if normalized.contains("chksz") { return true }
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
            return true
        case let .source(message):
            return allowsFallback(for: message)
        }
    }
}

public final class FallbackPlaybackURLResolver: PlaybackURLRefreshing, @unchecked Sendable {
    private let primary: PlaybackURLResolving
    private let sourceRuntime: SourceRuntime
    private let publicFallback: PlaybackURLResolving?

    public init(
        primary: PlaybackURLResolving,
        sourceRuntime: SourceRuntime,
        publicFallback: PlaybackURLResolving? = nil
    ) {
        self.primary = primary
        self.sourceRuntime = sourceRuntime
        self.publicFallback = publicFallback
    }

    public func musicURL(for track: Track, quality: Quality) async throws -> URL {
        try await resolve(track: track, quality: quality, refreshing: false)
    }

    public func refreshMusicURL(for track: Track, quality: Quality) async throws -> URL {
        try await resolve(track: track, quality: quality, refreshing: true)
    }

    private func resolve(track: Track, quality: Quality, refreshing: Bool) async throws -> URL {
        do {
            return try await resolvePrimary(track: track, quality: quality, refreshing: refreshing)
        } catch let primaryError as SourceError {
            guard primaryError.allowsPlaybackFallback else { throw primaryError }
            let alternateSource: MusicSource = track.source == .wy ? .tx : .wy
            do {
                let page = try await sourceRuntime.search("\(track.title) \(track.artist)", source: alternateSource, page: 1)
                try Task.checkCancellation()
                guard let replacement = bestMatch(for: track, candidates: page.list) else {
                    if let publicFallback {
                        return try await publicFallback.musicURL(for: track, quality: quality)
                    }
                    throw primaryError
                }
                return try await resolvePrimary(track: replacement, quality: quality, refreshing: refreshing)
            } catch is CancellationError {
                throw CancellationError()
            } catch let alternateError as SourceError {
                if let publicFallback, alternateError.allowsPlaybackFallback {
                    return try await publicFallback.musicURL(for: track, quality: quality)
                }
                throw alternateError
            }
        }
    }

    private func resolvePrimary(track: Track, quality: Quality, refreshing: Bool) async throws -> URL {
        if refreshing, let refreshable = primary as? PlaybackURLRefreshing {
            return try await refreshable.refreshMusicURL(for: track, quality: quality)
        }
        return try await primary.musicURL(for: track, quality: quality)
    }

    func bestMatch(for track: Track, candidates: [Track]) -> Track? {
        let targetTitle = Self.normalized(track.title)
        let targetArtist = Self.normalizedArtist(track.artist)
        let targetDuration = track.durationSeconds
        return candidates
            .map { candidate -> (Track, Int) in
                var score = 0
                let candidateTitle = Self.normalized(candidate.title)
                let candidateArtist = Self.normalizedArtist(candidate.artist)
                if candidateTitle == targetTitle { score += 100 }
                else if candidateTitle.contains(targetTitle) || targetTitle.contains(candidateTitle) { score += 55 }
                if candidateArtist == targetArtist { score += 60 }
                else if !targetArtist.isEmpty && (candidateArtist.contains(targetArtist) || targetArtist.contains(candidateArtist)) { score += 30 }
                if let targetDuration, let candidateDuration = candidate.durationSeconds, abs(targetDuration - candidateDuration) < 5 { score += 25 }
                return (candidate, score)
            }
            .filter { $0.1 >= 100 }
            .max { $0.1 < $1.1 }?
            .0
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func normalizedArtist(_ value: String) -> String {
        value.split(whereSeparator: { "、&;/,，|".contains($0) })
            .map { normalized(String($0)) }
            .sorted()
            .joined(separator: "|")
    }
}

private extension SourceError {
    var allowsPlaybackFallback: Bool {
        switch self {
        case .network:
            false
        case .credentialRequired:
            true
        case let .source(message):
            PlaybackFallbackPolicy.allowsFallback(for: message)
        }
    }
}

public final class PublicStreamPlaybackURLResolver: PlaybackURLResolving, @unchecked Sendable {
    private let client: PlaybackHTTPClient

    public init(client: PlaybackHTTPClient = URLSessionPlaybackHTTPClient()) {
        self.client = client
    }

    public func musicURL(for track: Track, quality: Quality) async throws -> URL {
        if let miguURL = try? await resolveMigu(track: track) {
            return miguURL
        }
        if let kuwoURL = try? await resolveKuwo(track: track) {
            return kuwoURL
        }
        throw SourceError.source(message: "公共备选音源未能匹配可用链接")
    }

    private func resolveMigu(track: Track) async throws -> URL {
        let query = "\(track.title) \(track.artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let apiURL = URL(string: "https://api.xcvts.cn/api/music/migu?gm=\(encoded)&n=1&num=1&type=json") else {
            throw SourceError.source(message: "咪咕: 请求地址无效")
        }
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 3.5

        let response = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw SourceError.source(message: "咪咕: HTTP \(response.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              let rawURL = json["music_url"] as? String,
              let url = URL(string: rawURL),
              url.scheme == "http" || url.scheme == "https" else {
            throw SourceError.source(message: "咪咕: 未返回可用播放链接")
        }
        try await validateMediaURL(url)
        return url
    }

    private func resolveKuwo(track: Track) async throws -> URL {
        let query = "\(track.title) \(track.artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let apiURL = URL(string: "https://oiapi.net/api/Kuwo?msg=\(encoded)&n=1&br=7") else {
            throw SourceError.source(message: "酷我: 请求地址无效")
        }
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 3.5

        let response = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw SourceError.source(message: "酷我: HTTP \(response.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
            throw SourceError.source(message: "酷我: JSON 异常")
        }
        var foundURLString: String?
        if let direct = json["url"] as? String {
            foundURLString = direct
        } else if let message = json["message"] as? String {
            for marker in ["音乐链接：", "音乐链接:"] {
                if let range = message.range(of: marker) {
                    let substr = message[range.upperBound...]
                    let end = substr.firstIndex(where: { $0.isWhitespace || $0.isNewline }) ?? substr.endIndex
                    foundURLString = String(substr[..<end])
                    break
                }
            }
        }
        guard let rawURL = foundURLString,
              let url = URL(string: rawURL),
              url.scheme == "http" || url.scheme == "https" else {
            throw SourceError.source(message: "酷我: 未返回可用播放链接")
        }
        try await validateMediaURL(url)
        return url
    }

    private func validateMediaURL(_ url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let response = try await client.probe(request, maxBytes: 64, timeout: 2.5)
        guard [200, 206].contains(response.statusCode) else {
            throw SourceError.source(message: "备选流媒体链接失效（HTTP \(response.statusCode)）")
        }
    }
}

