import Foundation
import Security

/// 网易云 Web 接口客户端（只读内容接口）。
///
/// 设计前提：接口走 `music.163.com` 的 legacy `/api/` 端点，只需要登录 Cookie `MUSIC_U`，
/// 不需要 eapi 加密。所有请求都带同一个 UA / Referer，避免风控命中。
///
/// Cookie 取值顺序：Keychain → UserDefaults（调试用）→ 环境变量。
public struct NetEaseCookieStore: Sendable {
    public static let keychainService = "cn.bobochang.sonar.netease"
    public static let keychainAccount = "MUSIC_U"
    public static let defaultsKey = "sonar.netease.cookie"
    public static let environmentKey = "SONAR_NETEASE_COOKIE"
    /// 勾选后优先使用包内 `wyToken`（长期 SVIP 凭证），忽略手动保存的账号 Cookie。
    public static let preferBundledKey = "sonar.netease.preferBundled"

    public init() {}

    public var cookie: String? {
        if UserDefaults.standard.bool(forKey: Self.preferBundledKey), let bundled = Self.bundledToken() {
            return bundled
        }
        if let value = Self.readKeychain(), !value.isEmpty { return value }
        if let value = UserDefaults.standard.string(forKey: Self.defaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment[Self.environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        return Self.bundledToken()
    }

    /// 构建产物里随包携带的备用登录态（`BuildCredentials.json` 的 `wyToken`）。
    /// 优先级最低：用户在设置页保存的 Cookie 永远覆盖它。
    private static func bundledToken() -> String? {
        guard let url = Bundle.main.url(forResource: "BuildCredentials", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["wyToken"] as? String else { return nil }
        return normalized(raw)
    }

    public var hasCookie: Bool { cookie != nil }

    /// 允许用户直接粘贴整段 Cookie，这里只取出 MUSIC_U 的值。
    public func save(_ raw: String?) throws {
        let value = Self.normalized(raw)
        let base: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var query = base
        query[kSecValueData] = Data(value.utf8)
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let range = trimmed.range(of: "MUSIC_U=") {
            let rest = trimmed[range.upperBound...]
            let end = rest.firstIndex(of: ";") ?? rest.endIndex
            let value = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return trimmed
    }

    private static func readKeychain() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public actor NetEaseWebClient {
    public enum Failure: Error, LocalizedError {
        case missingCookie
        case http(Int)
        case api(Int, String)
        case malformed(String)

        public var errorDescription: String? {
            switch self {
            case .missingCookie: "还没有配置网易云登录 Cookie"
            case let .http(code): "网易云接口返回 HTTP \(code)"
            case let .api(code, message): "网易云接口错误 \(code)：\(message)"
            case let .malformed(detail): "网易云接口数据异常：\(detail)"
            }
        }
    }

    public struct TrackQuality: Sendable {
        public let level: String
        public let bitrate: Int
        public let size: Int?
        public let format: String?
    }

    private let session: URLSession
    private let cookieStore: NetEaseCookieStore
    private var cache: [String: (value: Any, expiresAt: Date)] = [:]
    private let baseURL = URL(string: "https://music.163.com")!

    public init(cookieStore: NetEaseCookieStore = NetEaseCookieStore(), session: URLSession? = nil) {
        self.cookieStore = cookieStore
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            configuration.httpAdditionalHeaders = ["Accept": "application/json"]
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - 基础请求

    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> [String: Any] {
        var lastError: Error?
        for attempt in 0 ..< 2 {
            do {
                return try await performGet(path, query: query)
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as Failure {
                throw failure
            } catch {
                lastError = error
                if attempt == 0 {
                    try? await Task.sleep(for: .milliseconds(350))
                }
            }
        }
        throw lastError ?? Failure.http(0)
    }

    private func performGet(_ path: String, query: [URLQueryItem]) async throws -> [String: Any] {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw Failure.malformed(path) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        if let cookie = cookieStore.cookie {
            request.setValue("MUSIC_U=\(cookie); os=ios; appver=9.6.07", forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw Failure.http(http.statusCode)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.malformed(path)
        }
        if let code = object["code"] as? Int, code != 200 {
            let message = (object["message"] as? String) ?? (object["msg"] as? String) ?? ""
            throw Failure.api(code, message)
        }
        return object
    }

    private static let userAgent = "neteasemusic/9.6.07 (iPhone; iOS 27.0.1; Scale/3.00)"

    /// 校验登录态，同时返回昵称与会员档位，设置页用来确认 Cookie 是否有效。
    public func account() async throws -> (nickname: String, vipType: Int) {
        let object = try await get("/api/nuser/account/get")
        guard let profile = object["profile"] as? [String: Any] else {
            throw Failure.malformed("账号信息缺失")
        }
        let nickname = (profile["nickname"] as? String) ?? ""
        let vipType = Self.intValue((object["account"] as? [String: Any])?["vipType"]) ?? 0
        return (nickname, vipType)
    }

    // MARK: - 搜索

    public func searchSongs(_ keyword: String, limit: Int = 25, offset: Int = 0) async throws -> (tracks: [Track], total: Int) {
        let object = try await get("/api/search/get", query: [
            .init(name: "s", value: keyword),
            .init(name: "type", value: "1"),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
        ])
        let result = object["result"] as? [String: Any] ?? [:]
        let songs = result["songs"] as? [[String: Any]] ?? []
        let total = Self.intValue(result["songCount"]) ?? songs.count
        let tracks = songs.compactMap { Self.track(from: $0) }
        if !songs.isEmpty, tracks.isEmpty {
            throw Failure.malformed("搜索结果缺少曲目信息")
        }
        return (tracks, total)
    }

    public func searchArtists(_ keyword: String, limit: Int = 20, offset: Int = 0) async throws -> (artists: [ArtistSummary], total: Int) {
        let object = try await get("/api/search/get", query: [
            .init(name: "s", value: keyword),
            .init(name: "type", value: "100"),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
        ])
        let result = object["result"] as? [String: Any] ?? [:]
        let raw = result["artists"] as? [[String: Any]] ?? []
        let total = Self.intValue(result["artistCount"]) ?? raw.count
        let artists = raw.compactMap { Self.artist(from: $0) }
        return (artists, total)
    }

    public func searchAlbums(_ keyword: String, limit: Int = 20, offset: Int = 0) async throws -> (albums: [AlbumSummary], total: Int) {
        let object = try await get("/api/search/get", query: [
            .init(name: "s", value: keyword),
            .init(name: "type", value: "10"),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
        ])
        let result = object["result"] as? [String: Any] ?? [:]
        let raw = result["albums"] as? [[String: Any]] ?? []
        let total = Self.intValue(result["albumCount"]) ?? raw.count
        let albums = raw.compactMap { Self.album(from: $0) }
        return (albums, total)
    }

    public func hotSearches(limit: Int = 12) async throws -> [String] {
        let object = try await get("/api/search/hot", query: [.init(name: "type", value: "1111")])
        let result = object["result"] as? [String: Any] ?? [:]
        let hots = result["hots"] as? [[String: Any]] ?? []
        return hots.compactMap { ($0["first"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(limit)
            .map { $0 }
    }

    public func searchSuggestions(_ keyword: String, limit: Int = 8) async throws -> [String] {
        let object = try await get("/api/search/suggest/keyword", query: [.init(name: "s", value: keyword)])
        let result = object["result"] as? [String: Any] ?? [:]
        let matches = result["allMatch"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        return matches.compactMap { ($0["keyword"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 歌手 / 专辑

    public func artist(id: String, page: Int = 1, limit: Int = 50) async throws -> (artist: ArtistSummary, tracks: [Track]) {
        if let cached = cachedValue(for: "artist:\(id)") as? (artist: ArtistSummary, tracks: [Track]) {
            return cached
        }
        let object = try await get("/api/v1/artist/\(id)")
        let rawArtist = object["artist"] as? [String: Any] ?? [:]
        let hotSongs = object["hotSongs"] as? [[String: Any]] ?? []
        guard let artist = Self.artist(from: rawArtist) else {
            throw Failure.malformed("歌手信息缺失")
        }
        let result = (artist, hotSongs.compactMap { Self.track(from: $0) })
        store(result, for: "artist:\(id)")
        return result
    }

    public func artistAlbums(id: String, limit: Int = 24, offset: Int = 0) async throws -> [AlbumSummary] {
        let object = try await get("/api/artist/albums/\(id)", query: [
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
        ])
        let raw = object["hotAlbums"] as? [[String: Any]] ?? []
        return raw.compactMap { Self.album(from: $0) }
    }

    public func album(id: String) async throws -> AlbumDetail {
        if let cached = cachedValue(for: "album:\(id)") as? AlbumDetail {
            return cached
        }
        let object = try await get("/api/v1/album/\(id)")
        let rawAlbum = object["album"] as? [String: Any] ?? [:]
        let songs = object["songs"] as? [[String: Any]] ?? []
        guard let album = Self.album(from: rawAlbum) else {
            throw Failure.malformed("专辑信息缺失")
        }
        let detail = AlbumDetail(album: album, tracks: songs.compactMap { Self.track(from: $0) })
        store(detail, for: "album:\(id)")
        return detail
    }

    public func songDetail(ids: [String]) async throws -> [Track] {
        let object = try await get("/api/song/detail", query: [
            .init(name: "ids", value: "[\(ids.joined(separator: ","))]"),
        ])
        let songs = object["songs"] as? [[String: Any]] ?? []
        return songs.compactMap { Self.track(from: $0) }
    }

    // MARK: - 歌词 / 播放

    public func lyric(id: String) async throws -> LyricInfo {
        let object = try await get("/api/song/lyric", query: [
            .init(name: "id", value: id),
            .init(name: "lv", value: "-1"),
            .init(name: "kv", value: "-1"),
            .init(name: "tv", value: "-1"),
        ])
        func text(_ key: String) -> String? {
            guard let wrapper = object[key] as? [String: Any],
                  let value = wrapper["lyric"] as? String,
                  !value.isEmpty else { return nil }
            return value
        }
        guard let lrc = text("lrc") else {
            throw Failure.malformed("歌词为空")
        }
        return LyricInfo(lyric: lrc, tlyric: text("tlyric"), rlyric: text("romalrc"), lxlyric: text("klyric"))
    }

    public func privileges(ids: [String]) async throws -> [String: [String: Any]] {
        let object = try await get("/api/song/enhance/privilege", query: [
            .init(name: "ids", value: "[\(ids.joined(separator: ","))]"),
        ])
        let list = object["data"] as? [[String: Any]] ?? []
        var result: [String: [String: Any]] = [:]
        for item in list {
            if let id = Self.intValue(item["id"]) { result[String(id)] = item }
        }
        return result
    }

    public func songURL(id: String, level: String, encodeType: String) async throws -> TrackQuality {
        let object = try await get("/api/song/enhance/player/url/v1", query: [
            .init(name: "ids", value: "[\(id)]"),
            .init(name: "level", value: level),
            .init(name: "encodeType", value: encodeType),
        ])
        let list = object["data"] as? [[String: Any]] ?? []
        guard let item = list.first else { throw Failure.malformed("播放地址为空") }
        guard (item["url"] as? String)?.isEmpty == false else {
            let code = Self.intValue(item["code"]) ?? 0
            throw Failure.api(code, "没有可用播放地址")
        }
        return TrackQuality(
            level: (item["level"] as? String) ?? level,
            bitrate: Self.intValue(item["br"]) ?? 0,
            size: Self.intValue(item["size"]),
            format: item["type"] as? String
        )
    }

    public func playableURL(id: String, level: String, encodeType: String) async throws -> (url: URL, quality: TrackQuality) {
        let object = try await get("/api/song/enhance/player/url/v1", query: [
            .init(name: "ids", value: "[\(id)]"),
            .init(name: "level", value: level),
            .init(name: "encodeType", value: encodeType),
        ])
        let list = object["data"] as? [[String: Any]] ?? []
        guard let item = list.first,
              let raw = item["url"] as? String,
              let url = Self.mediaURL(raw) else {
            let code = list.first.flatMap { Self.intValue($0["code"]) } ?? 0
            throw Failure.api(code, "没有可用播放地址")
        }
        let quality = TrackQuality(
            level: (item["level"] as? String) ?? level,
            bitrate: Self.intValue(item["br"]) ?? 0,
            size: Self.intValue(item["size"]),
            format: item["type"] as? String
        )
        return (url, quality)
    }

    // MARK: - 歌单（搜索结果用）

    public func searchPlaylists(_ keyword: String, limit: Int = 20, offset: Int = 0) async throws -> (playlists: [PlaylistSummary], total: Int) {
        let object = try await get("/api/search/get", query: [
            .init(name: "s", value: keyword),
            .init(name: "type", value: "1000"),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
        ])
        let result = object["result"] as? [String: Any] ?? [:]
        let raw = result["playlists"] as? [[String: Any]] ?? []
        let total = Self.intValue(result["playlistCount"]) ?? raw.count
        let playlists = raw.compactMap { Self.playlist(from: $0) }
        return (playlists, total)
    }

    public func playlistDetail(id: String, limit: Int = 1000) async throws -> PlaylistDetail {
        let object = try await get("/api/v6/playlist/detail", query: [
            .init(name: "id", value: id),
            .init(name: "n", value: String(limit)),
        ])
        guard let raw = object["playlist"] as? [String: Any],
              let name = raw["name"] as? String else {
            throw Failure.malformed("歌单信息缺失")
        }
        let tracks = (raw["tracks"] as? [[String: Any]] ?? []).compactMap { Self.track(from: $0) }
        let total = Self.intValue(raw["trackCount"]) ?? tracks.count
        let creator = (raw["creator"] as? [String: Any])?["nickname"] as? String ?? ""
        let info = PlaylistDetailInfo(
            name: name,
            img: raw["coverImgUrl"] as? String,
            desc: raw["description"] as? String,
            author: creator,
            playCount: Self.intValue(raw["playCount"]).map(String.init) ?? ""
        )
        return PlaylistDetail(
            list: tracks,
            total: total,
            page: 1,
            limit: max(total, tracks.count),
            source: .wy,
            info: info
        )
    }

    static func playlist(from raw: [String: Any]) -> PlaylistSummary? {
        guard let id = Self.intValue(raw["id"]), let name = raw["name"] as? String else { return nil }
        return PlaylistSummary(
            id: String(id),
            name: name,
            img: raw["coverImgUrl"] as? String ?? raw["img"] as? String,
            author: (raw["creator"] as? [String: Any])?["nickname"] as? String ?? "",
            playCount: Self.intValue(raw["playCount"]).map(String.init) ?? "",
            total: Self.intValue(raw["trackCount"]),
            desc: raw["description"] as? String,
            time: nil,
            source: .wy
        )
    }

    // 详情类接口在同一页面会被重复请求（歌手页同时取元数据与热门歌曲），做 60s 内存缓存。
    private func cachedValue(for key: String) -> Any? {
        guard let entry = cache[key] else { return nil }
        guard entry.expiresAt > Date() else {
            cache.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    private func store(_ value: Any, for key: String, ttl: TimeInterval = 60) {
        cache[key] = (value, Date().addingTimeInterval(ttl))
        if cache.count > 64 {
            let now = Date()
            cache = cache.filter { $0.value.expiresAt > now }
        }
    }

    // MARK: - 映射

    static func mediaURL(_ raw: String) -> URL? {
        guard var components = URLComponents(string: raw),
              let host = components.host, !host.isEmpty,
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        components.scheme = "https"
        return components.url
    }

    static func artist(from raw: [String: Any]) -> ArtistSummary? {
        guard let id = Self.intValue(raw["id"]) ?? Self.intValue(raw["artistId"]), let name = raw["name"] as? String else { return nil }
        return try? ArtistSummary(
            id: String(id),
            source: .wy,
            name: name,
            imageURL: raw["picUrl"] as? String ?? raw["img1v1Url"] as? String,
            songCount: Self.intValue(raw["musicSize"]) ?? Self.intValue(raw["songSize"]),
            albumCount: Self.intValue(raw["albumSize"])
        )
    }

    static func album(from raw: [String: Any]) -> AlbumSummary? {
        guard let id = Self.intValue(raw["id"]), let name = raw["name"] as? String else { return nil }
        let artistName = (raw["artist"] as? [String: Any])?["name"] as? String
            ?? (raw["artists"] as? [[String: Any]])?.first?["name"] as? String
            ?? ""
        let publish = Self.intValue(raw["publishTime"]).map { Self.dateString(milliseconds: $0) }
        return try? AlbumSummary(
            id: String(id),
            source: .wy,
            name: name,
            artist: artistName,
            imageURL: raw["picUrl"] as? String ?? raw["blurPicUrl"] as? String,
            releaseDate: publish,
            trackCount: Self.intValue(raw["size"]) ?? Self.intValue(raw["trackCount"])
        )
    }

    static func track(from raw: [String: Any]) -> Track? {
        guard let id = Self.intValue(raw["id"]), let name = raw["name"] as? String else { return nil }
        let artists = (raw["ar"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
            ?? (raw["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
            ?? []
        let album = (raw["al"] as? [String: Any]) ?? (raw["album"] as? [String: Any]) ?? [:]
        var payload: [String: Any] = [
            "songmid": String(id),
            "name": name,
            "singer": artists.joined(separator: "/"),
            "albumName": (album["name"] as? String) ?? "",
        ]
        if let pic = (album["picUrl"] as? String) ?? (raw["picUrl"] as? String) {
            payload["picUrl"] = pic
        }
        if let albumID = Self.intValue(album["id"]) { payload["albumID"] = albumID }
        let artistList = (raw["ar"] as? [[String: Any]]) ?? (raw["artists"] as? [[String: Any]]) ?? []
        if let first = artistList.first, let artistID = Self.intValue(first["id"]) {
            payload["artistID"] = artistID
            if let name = first["name"] as? String { payload["artistName"] = name }
        }
        if let duration = Self.intValue(raw["dt"]) ?? Self.intValue(raw["duration"]) {
            payload["interval"] = Self.interval(milliseconds: duration)
        }
        payload["types"] = Self.qualityTypes(from: raw)
        if let st = Self.intValue(raw["st"]) { payload["st"] = st }
        if let fee = Self.intValue(raw["fee"]) { payload["fee"] = fee }
        if let privilege = raw["privilege"] as? [String: Any] { payload["privilege"] = privilege }
        return try? Track(source: .wy, raw: payload)
    }

    private static func qualityTypes(from raw: [String: Any]) -> [[String: String]] {
        var values: [[String: String]] = []
        func append(_ key: String, quality: Quality) {
            guard let entry = raw[key] as? [String: Any] else { return }
            let size = Self.intValue(entry["size"]) ?? Self.intValue(entry["filesize"]) ?? 0
            guard size > 0 else { return }
            values.append(["type": quality.rawValue, "size": String(size)])
        }
        append("l", quality: .standard)
        append("h", quality: .high)
        append("sq", quality: .lossless)
        append("hr", quality: .hiRes)
        return values
    }

    static func dateString(milliseconds: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000))
    }

    static func interval(milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1000)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int: value
        case let value as Int64: Int(value)
        case let value as Double: Int(value)
        case let value as NSNumber: value.intValue
        case let value as String: Int(value)
        default: nil
        }
    }
}
