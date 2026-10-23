import Foundation

public protocol ChkszAPIRequesting: Sendable {
    func request(path: String, parameters: [String: String]) async throws -> Data
}

public final class ChkszAPIClient: ChkszAPIRequesting, @unchecked Sendable {
    private let client: PlaybackHTTPClient
    private let credentials: CredentialStore
    private let breaker: ChkszCircuitBreaker
    private let requestTimeout: TimeInterval

    public init(
        client: PlaybackHTTPClient = URLSessionPlaybackHTTPClient(),
        credentials: CredentialStore,
        breaker: ChkszCircuitBreaker = ChkszCircuitBreaker(),
        requestTimeout: TimeInterval = 8
    ) {
        self.client = client
        self.credentials = credentials
        self.breaker = breaker
        self.requestTimeout = requestTimeout.isFinite && requestTimeout > 0 ? min(requestTimeout, 30) : 8
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
        request.timeoutInterval = requestTimeout
        var response = try await client.send(request)
        if response.statusCode == 429 {
            let retry = Self.retryDelay(from: response)
            if retry <= 10 {
                try await Task.sleep(for: .seconds(max(0, retry)))
                response = try await client.send(request)
            }
        }

        try await validateHTTP(response, path: path, parameters: parameters)
        try await validateEnvelope(response.body)
        return response.body
    }

    private func validateHTTP(_ response: PlaybackHTTPResponse, path: String, parameters: [String: String]) async throws {
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
            let isSongSearch = path.hasSuffix("music") && parameters["msg"] != nil
                && ["id", "mid", "n"].allSatisfy { parameters[$0] == nil }
            let operation = isSongSearch ? "搜索" : path.hasSuffix("music") ? "播放解析" : path.hasSuffix("lyric") ? "歌词请求"
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

/// Active song sources use ChKSz. The QQ adapter remains for persisted data and
/// a future restoration, but hidden sources never receive new requests.
public final class ChkszSourceRuntime: SourceRuntime, @unchecked Sendable {
    private let netease: ChkszNetEaseProviding

    // Retain the injection signature for existing local clients without activating retired providers.
    public init(qq: SourceRuntime? = nil, netease: ChkszNetEaseProviding, kugou: ChkszKugouProviding? = nil) {
        self.netease = netease
    }

    public func search(_ keyword: String, source: MusicSource, page: Int) async throws -> SearchPage {
        try source.requireEnabled()
        return try await netease.search(keyword, page: page, limit: 25)
    }

    public func lyric(_ track: Track) async throws -> LyricInfo {
        if track.source == .local {
            return Self.resolveLocalLyric(track)
        }
        try track.source.requireEnabled()
        return try await netease.lyric(track)
    }

    public static func resolveLocalLyric(_ track: Track) -> LyricInfo {
        let path = (track.rawPayload["filePath"] as? String) ?? track.songmid
        guard !path.isEmpty else { return LyricInfo(lyric: "", tlyric: nil) }
        let audioURL = URL(fileURLWithPath: path)
        let lrcURL = audioURL.deletingPathExtension().appendingPathExtension("lrc")
        if FileManager.default.fileExists(atPath: lrcURL.path),
           let content = try? String(contentsOf: lrcURL, encoding: .utf8) {
            return LyricInfo(lyric: content, tlyric: nil)
        }
        return LyricInfo(lyric: "", tlyric: nil)
    }

    public func picURL(_ track: Track) async throws -> URL {
        if track.source == .local {
            let path = (track.rawPayload["filePath"] as? String) ?? track.songmid
            return URL(fileURLWithPath: path)
        }
        try track.source.requireEnabled()
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
        try track.source.requireEnabled()
        return track
    }

    public func tipSearch(_ keyword: String) async throws -> [String] { [] }
}

public struct ChkszPlaybackResult: Sendable, Equatable {
    public let url: URL
    public let actualQuality: Quality

    public init(url: URL, actualQuality: Quality) {
        self.url = url
        self.actualQuality = actualQuality
    }
}

public protocol ChkszKugouProviding: Sendable {
    func search(_ keyword: String, page: Int) async throws -> SearchPage
    func lyric(_ track: Track) async throws -> LyricInfo
    func picURL(_ track: Track) async throws -> URL
    func trackDetail(_ track: Track) async throws -> Track
    func musicURL(for track: Track, quality: Quality) async throws -> ChkszPlaybackResult
}

public final class ChkszKugouClient: ChkszKugouProviding, @unchecked Sendable {
    private let api: ChkszAPIRequesting
    private let metadata = KugouMetadataCache()

    public init(api: ChkszAPIRequesting) { self.api = api }

    public func search(_ keyword: String, page: Int = 1) async throws -> SearchPage {
        try MusicSource.kg.requireEnabled()
        // The documented endpoint returns one bounded list and has no page parameter.
        guard page <= 1 else { return SearchPage(list: [], total: 0, allPage: 1) }
        let data = try await api.request(path: "/api/kugou_music", parameters: ["msg": keyword, "type": "json"])
        let object = try Self.object(data)
        guard let songs = object["list"] as? [[String: Any]] else {
            throw SourceError.source(message: "酷狗搜索返回数据异常")
        }
        let tracks = songs.compactMap { song -> Track? in
            guard let id = Self.string(song["id"]),
                  let name = Self.string(song["name"]),
                  let singer = Self.string(song["singer"]) else { return nil }
            var raw: [String: Any] = ["songmid": id, "name": name, "singer": singer, "albumName": Self.string(song["album"]) ?? ""]
            if let seconds = song["duration"] as? NSNumber, seconds.intValue > 0 {
                raw["interval"] = String(format: "%d:%02d", seconds.intValue / 60, seconds.intValue % 60)
            }
            if let cover = Self.string(song["cover"]), let url = Self.mediaURL(cover) { raw["img"] = url.absoluteString }
            return try? Track(source: .kg, raw: raw)
        }
        guard songs.isEmpty || !tracks.isEmpty else {
            throw SourceError.source(message: "酷狗搜索结果缺少曲目信息")
        }
        return SearchPage(list: tracks, total: tracks.count, allPage: 1)
    }

    public func musicURL(for track: Track, quality: Quality) async throws -> ChkszPlaybackResult {
        let data = try await detail(track, quality: quality)
        let object = try Self.object(data)
        guard let value = Self.string(object["url"]), let url = Self.mediaURL(value) else {
            throw SourceError.source(message: "酷狗播放未返回可用链接")
        }
        return ChkszPlaybackResult(url: url, actualQuality: PlaybackURLResolver.chkszQuality(from: object))
    }

    public func lyric(_ track: Track) async throws -> LyricInfo {
        try Self.requireTrack(track)
        let data: Data
        if let cached = await metadata.value(for: track.songmid) { data = cached }
        else { data = try await detail(track, quality: .master) }
        let object = try Self.object(data)
        guard let lyric = object["lrc"] as? String else {
            throw SourceError.source(message: "酷狗暂未提供歌词")
        }
        return LyricInfo(lyric: lyric, tlyric: nil, rlyric: nil, lxlyric: nil)
    }

    public func picURL(_ track: Track) async throws -> URL {
        try Self.requireTrack(track)
        let raw = track.rawPayload
        if let cover = Self.string(raw["img"] ?? raw["picUrl"]), let url = Self.mediaURL(cover) { return url }
        if let data = await metadata.value(for: track.songmid),
           let cover = Self.string(try Self.object(data)["cover"]), let url = Self.mediaURL(cover) { return url }
        // Do not resolve audio for every visible search row just to retrieve an optional cover.
        throw SourceError.source(message: "酷狗歌曲暂无封面")
    }

    public func trackDetail(_ track: Track) async throws -> Track {
        try Self.requireTrack(track)
        guard let data = await metadata.value(for: track.songmid) else { return track }
        let object = try Self.object(data)
        var raw = track.rawPayload
        if let cover = Self.string(object["cover"]), let url = Self.mediaURL(cover) { raw["img"] = url.absoluteString }
        if let interval = Self.string(object["interval"]) { raw["interval"] = interval }
        return try Track(source: .kg, raw: raw)
    }

    private func detail(_ track: Track, quality: Quality) async throws -> Data {
        try Self.requireTrack(track)
        let size: String = switch quality {
        case .standard: "128k"
        case .high: "320k"
        case .lossless: "flac"
        case .hiRes: "hires"
        case .master: "master"
        }
        let data = try await api.request(path: "/api/kugou_music", parameters: ["id": track.songmid, "size": size, "type": "json"])
        let object = try Self.object(data)
        guard let id = Self.string(object["id"]), id.caseInsensitiveCompare(track.songmid) == .orderedSame else {
            throw SourceError.source(message: "酷狗返回曲目与所选歌曲不一致")
        }
        await metadata.insert(data, for: track.songmid)
        return data
    }

    private static func requireTrack(_ track: Track) throws {
        try track.source.requireEnabled()
        guard track.source == .kg, !track.songmid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SourceError.source(message: "酷狗歌曲标识无效")
        }
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceError.source(message: "酷狗返回 JSON 异常")
        }
        return object
    }

    private static func string(_ value: Any?) -> String? {
        let value = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (value as? NSNumber)?.stringValue
        return value?.isEmpty == false ? value : nil
    }

    private static func mediaURL(_ value: String) -> URL? {
        guard var url = URLComponents(string: value),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        url.scheme = "https"
        return url.url
    }
}

private actor KugouMetadataCache {
    private var entries: [String: (expires: Date, data: Data)] = [:]

    func value(for id: String) -> Data? {
        guard let entry = entries[id], entry.expires > Date() else {
            entries[id] = nil
            return nil
        }
        return entry.data
    }

    func insert(_ data: Data, for id: String) {
        guard data.count <= 256 * 1024 else { return }
        entries[id] = (Date().addingTimeInterval(20 * 60), data)
        if entries.count > 40, let oldest = entries.min(by: { $0.value.expires < $1.value.expires })?.key {
            entries[oldest] = nil
        }
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
