import Foundation

public protocol ChkszAPIRequesting: Sendable {
    func request(path: String, parameters: [String: String]) async throws -> Data
}

public final class ChkszAPIClient: ChkszAPIRequesting, @unchecked Sendable {
    private let client: PlaybackHTTPClient
    private let credentials: CredentialStore
    private let breaker: ChkszCircuitBreaker

    public init(
        client: PlaybackHTTPClient = URLSessionPlaybackHTTPClient(),
        credentials: CredentialStore,
        breaker: ChkszCircuitBreaker = ChkszCircuitBreaker()
    ) {
        self.client = client
        self.credentials = credentials
        self.breaker = breaker
    }

    public func request(path: String, parameters: [String: String]) async throws -> Data {
        guard let key = credentials.chkszKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            throw SourceError.credentialRequired(hint: "未配置 ChKSz Key，备用音源不可用")
        }
        if let blockedMessage = await breaker.blockedMessage() {
            throw SourceError.source(message: blockedMessage)
        }

        var trustedParameters = parameters
        trustedParameters["apikey"] = key
        var components = URLComponents(string: "https://api.chksz.com" + path)!
        components.queryItems = trustedParameters
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else {
            throw SourceError.source(message: "ChKSz 请求地址异常")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        var response = try await client.send(request)
        if response.statusCode == 429 {
            let retry = Self.retryDelay(from: response)
            if retry <= 10 {
                try await Task.sleep(for: .seconds(max(0, retry)))
                response = try await client.send(request)
            }
        }

        try await validateHTTP(response)
        try await validateEnvelope(response.body)
        return response.body
    }

    private func validateHTTP(_ response: PlaybackHTTPResponse) async throws {
        switch response.statusCode {
        case 200:
            return
        case 401, 403:
            await breaker.disable(reason: "HTTP " + String(response.statusCode))
            throw SourceError.source(message: "ChKSz 凭证无效或已过期（HTTP " + String(response.statusCode) + "）")
        case 402:
            await breaker.disable(reason: "HTTP 402")
            throw SourceError.source(message: "ChKSz 额度已耗尽（HTTP 402）")
        case 429:
            await breaker.deferAfterRateLimit(seconds: Self.retryDelay(from: response))
            throw SourceError.source(message: "ChKSz 请求过于频繁（HTTP 429）")
        default:
            throw SourceError.source(message: "ChKSz: HTTP " + String(response.statusCode))
        }
    }

    private func validateEnvelope(_ data: Data) async throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceError.source(message: "ChKSz 返回 JSON 异常")
        }
        guard let code = Self.integer(object["code"]) else { return }
        switch code {
        case 200:
            return
        case 401, 403:
            await breaker.disable(reason: "API " + String(code))
            throw SourceError.source(message: "ChKSz 凭证无效或已过期（API " + String(code) + "）")
        case 402:
            await breaker.disable(reason: "API 402")
            throw SourceError.source(message: "ChKSz 额度已耗尽（API 402）")
        case 429:
            await breaker.deferAfterRateLimit(seconds: 5)
            throw SourceError.source(message: "ChKSz 请求过于频繁（API 429）")
        default:
            let message = (object["msg"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = message.flatMap { $0.isEmpty ? nil : $0 }
                ?? "ChKSz 返回异常（API " + String(code) + "）"
            throw SourceError.source(message: detail)
        }
    }

    private static func retryDelay(from response: PlaybackHTTPResponse) -> TimeInterval {
        let value = response.headers.first {
            $0.key.caseInsensitiveCompare("retry-after") == .orderedSame
        }?.value
        return Double(value ?? "5") ?? 5
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }
}

public struct ChkszPlaybackResult: Sendable, Equatable {
    public let url: URL
    public let actualQuality: Quality

    public init(url: URL, actualQuality: Quality) {
        self.url = url
        self.actualQuality = actualQuality
    }
}

public protocol ChkszNetEaseProviding: Sendable {
    func search(_ keyword: String, page: Int, limit: Int) async throws -> SearchPage
    func lyric(_ track: Track) async throws -> LyricInfo
    func musicURL(for track: Track, quality: Quality) async throws -> ChkszPlaybackResult
}

public final class ChkszNetEaseClient: ChkszNetEaseProviding, @unchecked Sendable {
    private let api: ChkszAPIRequesting

    public init(api: ChkszAPIRequesting) {
        self.api = api
    }

    public func search(_ keyword: String, page: Int = 1, limit: Int = 25) async throws -> SearchPage {
        let normalizedPage = max(page, 1)
        let normalizedLimit = min(max(limit, 1), 100)
        let data = try await api.request(
            path: "/api/163_search",
            parameters: [
                "keyword": keyword,
                "limit": String(normalizedLimit),
                "offset": String((normalizedPage - 1) * normalizedLimit),
            ]
        )
        let object = try Self.object(from: data)
        let payload = object["data"]
        let songs: [[String: Any]]
        let total: Int
        if let container = payload as? [String: Any] {
            songs = container["songs"] as? [[String: Any]] ?? []
            total = Self.integer(container["total"]) ?? songs.count
        } else if let documentedSongs = payload as? [[String: Any]] {
            songs = documentedSongs
            total = documentedSongs.count
        } else {
            throw SourceError.source(message: "ChKSz 网易搜索返回数据异常")
        }

        let tracks = songs.compactMap { try? Self.track(from: $0) }
        if !songs.isEmpty, tracks.isEmpty {
            throw SourceError.source(message: "ChKSz 网易搜索结果缺少曲目信息")
        }
        let allPage = max(1, Int(ceil(Double(max(total, tracks.count)) / Double(normalizedLimit))))
        return SearchPage(list: tracks, total: total, allPage: allPage)
    }

    public func lyric(_ track: Track) async throws -> LyricInfo {
        let data = try await api.request(
            path: "/api/163_lyric",
            parameters: ["id": track.songmid]
        )
        let object = try Self.object(from: data)
        guard let payload = object["data"] as? [String: Any],
              let lyric = payload["lrc"] as? String else {
            throw SourceError.source(message: "ChKSz 网易歌词返回数据异常")
        }
        return LyricInfo(
            lyric: lyric,
            tlyric: Self.nonEmptyString(payload["tlyric"]),
            rlyric: Self.nonEmptyString(payload["romalrc"]),
            lxlyric: Self.nonEmptyString(payload["klyric"])
        )
    }

    public func musicURL(for track: Track, quality: Quality) async throws -> ChkszPlaybackResult {
        let level: String = switch quality {
        case .standard: "standard"
        case .high: "exhigh"
        case .lossless: "lossless"
        case .hiRes: "hires"
        }
        let data = try await api.request(
            path: "/api/163_music",
            parameters: [
                "id": track.songmid,
                "level": level,
                "type": "json",
            ]
        )
        let object = try Self.object(from: data)
        guard let payload = object["data"] as? [String: Any],
              let rawURL = payload["url"] as? String,
              let url = URL(string: rawURL),
              Self.isHTTP(url) else {
            throw SourceError.source(message: "ChKSz 网易播放未返回可用链接")
        }
        return ChkszPlaybackResult(
            url: url,
            actualQuality: Self.quality(level: payload["level"] as? String, bitrate: Self.integer(payload["br"]), fallback: quality)
        )
    }

    private static func track(from song: [String: Any]) throws -> Track {
        guard let songID = string(song["id"]),
              let name = nonEmptyString(song["name"]),
              let artist = artistName(song["artists"]) else {
            throw SourceError.source(message: "ChKSz 网易搜索结果缺少曲目信息")
        }
        var raw: [String: Any] = [
            "songmid": songID,
            "name": name,
            "singer": artist,
            "albumName": nonEmptyString(song["album"]) ?? "",
        ]
        if let duration = integer(song["duration"]), duration > 0 {
            raw["interval"] = interval(milliseconds: duration)
        }
        if let picURL = nonEmptyString(song["picUrl"]), let url = URL(string: picURL), isHTTP(url) {
            raw["picUrl"] = picURL
        }
        return try Track(source: .wy, raw: raw)
    }

    private static func artistName(_ value: Any?) -> String? {
        if let name = nonEmptyString(value) { return name }
        if let names = value as? [String] {
            let joined = names.compactMap { nonEmptyString($0) }.joined(separator: "、")
            return joined.isEmpty ? nil : joined
        }
        if let artists = value as? [[String: Any]] {
            let joined = artists.compactMap { nonEmptyString($0["name"]) }.joined(separator: "、")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func interval(milliseconds: Int) -> String {
        let seconds = max(milliseconds / 1_000, 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func quality(level: String?, bitrate: Int?, fallback: Quality) -> Quality {
        switch level?.lowercased() {
        case "standard": return .standard
        case "exhigh": return .high
        case "lossless": return .lossless
        case "hires", "jymaster", "sky", "jyeffect": return .hiRes
        default:
            if let bitrate {
                if bitrate >= 1_500_000 { return .hiRes }
                if bitrate >= 700_000 { return .lossless }
                if bitrate >= 300_000 { return .high }
                return .standard
            }
            return fallback
        }
    }

    private static func object(from data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceError.source(message: "ChKSz 返回 JSON 异常")
        }
        return object
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string)
        default: return nil
        }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string.isEmpty ? nil : string
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isHTTP(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased())
    }
}

public final class FallbackSourceRuntime: SourceRuntime, @unchecked Sendable {
    private let primary: SourceRuntime
    private let neteaseFallback: ChkszNetEaseProviding

    public init(primary: SourceRuntime, neteaseFallback: ChkszNetEaseProviding) {
        self.primary = primary
        self.neteaseFallback = neteaseFallback
    }

    public func search(_ keyword: String, source: MusicSource, page: Int) async throws -> SearchPage {
        guard source == .wy else {
            return try await primary.search(keyword, source: source, page: page)
        }

        var emptyPrimary: SearchPage?
        do {
            let result = try await primary.search(keyword, source: source, page: page)
            if !result.list.isEmpty { return result }
            emptyPrimary = result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The fallback error is more actionable when the primary path failed.
        }

        do {
            return try await neteaseFallback.search(keyword, page: page, limit: 25)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let emptyPrimary { return emptyPrimary }
            throw error
        }
    }

    public func lyric(_ track: Track) async throws -> LyricInfo {
        guard track.source == .wy else { return try await primary.lyric(track) }
        do {
            return try await primary.lyric(track)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await neteaseFallback.lyric(track)
        }
    }

    public func picURL(_ track: Track) async throws -> URL {
        if track.source == .wy,
           let value = track.rawPayload["picUrl"] as? String,
           let url = URL(string: value),
           ["http", "https"].contains(url.scheme?.lowercased()) {
            return url
        }
        return try await primary.picURL(track)
    }

    public func tipSearch(_ keyword: String) async throws -> [String] {
        try await primary.tipSearch(keyword)
    }

    public func hotSearch(source: MusicSource) async throws -> [String] {
        try await primary.hotSearch(source: source)
    }

    public func playlistCatalog(source: MusicSource, sortId: String, tagId: String?, page: Int) async throws -> PlaylistCatalogPage {
        try await primary.playlistCatalog(source: source, sortId: sortId, tagId: tagId, page: page)
    }

    public func playlistDetail(source: MusicSource, id: String, page: Int) async throws -> PlaylistDetail {
        try await primary.playlistDetail(source: source, id: id, page: page)
    }

    public func searchArtists(_ keyword: String, source: MusicSource, page: Int) async throws -> ArtistSearchPage {
        try await primary.searchArtists(keyword, source: source, page: page)
    }

    public func searchArtists(
        _ keyword: String,
        source: MusicSource,
        page: Int,
        limit: Int
    ) async throws -> ArtistSearchPage {
        try await primary.searchArtists(keyword, source: source, page: page, limit: limit)
    }

    public func artistPopularTracks(_ artist: ArtistSummary) async throws -> [Track] {
        try await primary.artistPopularTracks(artist)
    }

    public func artistAlbums(_ artist: ArtistSummary, page: Int) async throws -> AlbumPage {
        try await primary.artistAlbums(artist, page: page)
    }

    public func albumTracks(_ album: AlbumSummary) async throws -> AlbumDetail {
        try await primary.albumTracks(album)
    }

    public func trackDetail(_ track: Track) async throws -> Track {
        try await primary.trackDetail(track)
    }
}
