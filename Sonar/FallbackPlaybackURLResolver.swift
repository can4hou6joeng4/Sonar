import Foundation

public final class HighestAvailableQualityPlaybackURLResolver: PlaybackURLResolving, @unchecked Sendable {
    private static let qualityOrder: [Quality] = [.hiRes, .lossless, .high, .standard]

    private let resolver: PlaybackURLResolving

    public init(resolver: PlaybackURLResolving) {
        self.resolver = resolver
    }

    public func musicURL(for track: Track, quality: Quality) async throws -> URL {
        guard let startingIndex = Self.qualityOrder.firstIndex(of: quality) else {
            return try await resolver.musicURL(for: track, quality: quality)
        }

        var eligibleFailures: [SourceError] = []
        for candidate in Self.qualityOrder[startingIndex...] {
            try Task.checkCancellation()
            do {
                return try await resolver.musicURL(for: track, quality: candidate)
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

}

private enum PlaybackFallbackPolicy {
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
        ].contains { normalized.contains($0) }
            || normalized == "未返回可用链接"
            || normalized == "qq: 未返回可用链接"
    }
}

public final class FallbackPlaybackURLResolver: PlaybackURLResolving, @unchecked Sendable {
    private let primary: PlaybackURLResolving
    private let sourceRuntime: SourceRuntime

    public init(primary: PlaybackURLResolving, sourceRuntime: SourceRuntime) {
        self.primary = primary
        self.sourceRuntime = sourceRuntime
    }

    public func musicURL(for track: Track, quality: Quality) async throws -> URL {
        do {
            return try await primary.musicURL(for: track, quality: quality)
        } catch let primaryError as SourceError {
            guard track.source == .wy, primaryError.allowsPlaybackFallback else { throw primaryError }
            do {
                let page = try await sourceRuntime.search("\(track.title) \(track.artist)", source: .tx, page: 1)
                try Task.checkCancellation()
                guard let replacement = bestMatch(for: track, candidates: page.list) else { throw primaryError }
                return try await primary.musicURL(for: replacement, quality: quality)
            } catch is CancellationError {
                throw CancellationError()
            } catch let alternateError as SourceError {
                throw alternateError
            }
        }
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
