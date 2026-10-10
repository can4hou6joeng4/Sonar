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
            throw SourceError.credentialRequired(hint: "未配置第三方音源凭据，暂不可用")
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
        request.timeoutInterval = 4.0
        var response = try await client.send(request)
        if response.statusCode == 429 {
            let retry = Self.retryDelay(from: response)
            if retry <= 10 {
                try await Task.sleep(for: .seconds(max(0, retry)))
                response = try await client.send(request)
            }
        }

        try await validateHTTP(response, path: path)
        try await validateEnvelope(response.body)
        return response.body
    }

    private func validateHTTP(_ response: PlaybackHTTPResponse, path: String) async throws {
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
            let operation = path.hasSuffix("music") ? "播放解析" : path.hasSuffix("lyric") ? "歌词请求"
                : path.hasSuffix("playlist") ? "歌单读取" : "搜索"
            throw SourceError.source(message: "第三方\(operation)失败（HTTP " + String(response.statusCode) + "）")
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
            let rawDetail = message.flatMap { $0.isEmpty ? nil : $0 }
                ?? "返回异常（API " + String(code) + "）"
            let detail = rawDetail.lowercased().contains("chksz") ? rawDetail : "ChKSz: " + rawDetail
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

/// QQ catalog requests retain their JavaScript adapter. NetEase song requests
/// go directly to ChKSz, without restoring the retired NetEase client APIs.
public final class ChkszSourceRuntime: SourceRuntime, @unchecked Sendable {
    private let qq: SourceRuntime
    private let netease: ChkszNetEaseProviding

    public init(qq: SourceRuntime, netease: ChkszNetEaseProviding) {
        self.qq = qq
        self.netease = netease
    }

    public func search(_ keyword: String, source: MusicSource, page: Int) async throws -> SearchPage {
        switch source {
        case .tx: try await qq.search(keyword, source: source, page: page)
        case .wy: try await netease.search(keyword, page: page, limit: 25)
        }
    }

    public func lyric(_ track: Track) async throws -> LyricInfo {
        switch track.source {
        case .tx: try await qq.lyric(track)
        case .wy: try await netease.lyric(track)
        }
    }

    public func picURL(_ track: Track) async throws -> URL {
        guard track.source == .wy else { return try await qq.picURL(track) }
        let payload = track.rawPayload
        let candidate = (payload["picUrl"] as? String)
            ?? (payload["img"] as? String)
            ?? ((payload["al"] as? [String: Any])?["picUrl"] as? String)
            ?? ((payload["album"] as? [String: Any])?["picUrl"] as? String)
        guard let candidate, var components = URLComponents(string: candidate),
              ["http", "https"].contains(components.scheme?.lowercased()),
              components.host?.isEmpty == false,
              components.user == nil, components.password == nil else {
            throw SourceError.source(message: "网易云歌曲暂无封面")
        }
        components.scheme = "https"
        guard let url = components.url else { throw SourceError.source(message: "封面地址异常") }
        return url
    }

    public func trackDetail(_ track: Track) async throws -> Track {
        track.source == .wy ? track : try await qq.trackDetail(track)
    }

    public func tipSearch(_ keyword: String) async throws -> [String] {
        try await qq.tipSearch(keyword)
    }

    public func hotSearch(source: MusicSource) async throws -> [String] {
        try source.requireQQClientSupport()
        return try await qq.hotSearch(source: source)
    }

    public func playlistSearch(_ keyword: String, source: MusicSource, page: Int) async throws -> PlaylistCatalogPage {
        try source.requireQQClientSupport()
        return try await qq.playlistSearch(keyword, source: source, page: page)
    }

    public func playlistCatalog(source: MusicSource, sortId: String, tagId: String?, page: Int) async throws -> PlaylistCatalogPage {
        try source.requireQQClientSupport()
        return try await qq.playlistCatalog(source: source, sortId: sortId, tagId: tagId, page: page)
    }

    public func playlistDetail(source: MusicSource, id: String, page: Int) async throws -> PlaylistDetail {
        try source.requireQQClientSupport()
        return try await qq.playlistDetail(source: source, id: id, page: page)
    }

    public func searchArtists(_ keyword: String, source: MusicSource, page: Int) async throws -> ArtistSearchPage {
        try await searchArtists(keyword, source: source, page: page, limit: 25)
    }

    public func searchArtists(_ keyword: String, source: MusicSource, page: Int, limit: Int) async throws -> ArtistSearchPage {
        try source.requireQQClientSupport()
        return try await qq.searchArtists(keyword, source: source, page: page, limit: limit)
    }

    public func artistPopularTracks(_ artist: ArtistSummary) async throws -> [Track] {
        try artist.source.requireQQClientSupport()
        return try await qq.artistPopularTracks(artist)
    }

    public func artistAlbums(_ artist: ArtistSummary, page: Int) async throws -> AlbumPage {
        try artist.source.requireQQClientSupport()
        return try await qq.artistAlbums(artist, page: page)
    }

    public func albumTracks(_ album: AlbumSummary) async throws -> AlbumDetail {
        try album.source.requireQQClientSupport()
        return try await qq.albumTracks(album)
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
        try Self.requireNetEaseTrack(track)
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
        try Self.requireNetEaseTrack(track)
        let level: String = switch quality {
        case .standard: "standard"
        case .high: "exhigh"
        case .lossless: "lossless"
        case .hiRes: "hires"
        case .master: "jymaster"
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
              let url = Self.normalizedURL(rawURL) else {
            throw SourceError.source(message: "ChKSz 网易播放未返回可用链接")
        }
        return ChkszPlaybackResult(
            url: url,
            actualQuality: Self.quality(level: payload["level"] as? String, bitrate: Self.integer(payload["br"]))
        )
    }

    private static func track(from song: [String: Any]) throws -> Track {
        guard let songID = string(song["id"]), Int64(songID).map({ $0 > 0 }) == true,
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
        if let picURL = nonEmptyString(song["picUrl"]), let url = normalizedURL(picURL) {
            raw["picUrl"] = url.absoluteString
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

    private static func quality(level: String?, bitrate: Int?) -> Quality {
        switch level?.lowercased() {
        case "standard": return .standard
        case "exhigh": return .high
        case "lossless": return .lossless
        case "jymaster": return .master
        case "hires", "sky", "jyeffect": return .hiRes
        default:
            if let bitrate {
                if bitrate >= 1_500_000 { return .hiRes }
                if bitrate >= 700_000 { return .lossless }
                if bitrate >= 300_000 { return .high }
                return .standard
            }
            return .standard
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

    private static func requireNetEaseTrack(_ track: Track) throws {
        guard track.source == .wy, Int64(track.songmid).map({ $0 > 0 }) == true else {
            throw SourceError.source(message: "网易云歌曲标识无效")
        }
    }

    private static func normalizedURL(_ value: String) -> URL? {
        guard var components = URLComponents(string: value),
              ["http", "https"].contains(components.scheme?.lowercased()),
              components.host?.isEmpty == false,
              components.user == nil, components.password == nil else { return nil }
        components.scheme = "https"
        return components.url
    }
}
