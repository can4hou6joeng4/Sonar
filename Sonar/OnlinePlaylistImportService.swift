import Foundation

public enum OnlinePlaylistImportError: Error, LocalizedError, Equatable {
    case invalidInput
    case unsupportedLink
    case notPlaylistLink
    case unavailable
    case invalidResponse
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidInput: "请粘贴歌单分享链接，或选择音源后输入有效的歌单 ID。"
        case .unsupportedLink: "暂时只支持 QQ 音乐和网易云音乐的歌单分享链接。"
        case .notPlaylistLink: "未找到歌单 ID。请复制完整的歌单分享链接，歌曲和个人主页链接不能用于导入。"
        case .unavailable: "无法读取这个歌单。请确认歌单公开且仍然存在，或稍后重试。"
        case .invalidResponse: "歌单返回的数据不完整，请稍后重试。现有歌曲会保留。"
        case .tooLarge: "目前一次最多读取 5,000 首歌曲，请分成较小的歌单后导入。"
        }
    }
}

public struct OnlinePlaylistReference: Equatable, Sendable {
    public let source: MusicSource
    public let id: String

    static func normalizedID(_ value: String) -> String? {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              value.count <= 18, let number = Int64(value), number > 0 else { return nil }
        return String(number)
    }

    static func source(for url: URL) -> MusicSource? {
        switch url.host?.lowercased() {
        case "music.163.com", "y.music.163.com", "163cn.tv": .wy
        case "y.qq.com", "i.y.qq.com", "c.y.qq.com", "u.y.qq.com": .tx
        default: nil
        }
    }

    static func from(url: URL) throws -> OnlinePlaylistReference {
        guard let source = source(for: url), let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.port == nil,
              ["http", "https"].contains(components.scheme?.lowercased() ?? "") else {
            throw OnlinePlaylistImportError.unsupportedLink
        }
        let fragment = components.fragment.flatMap { URLComponents(string: $0) }
        let paths = [components.path, fragment?.path ?? ""].map { $0.lowercased() }
        let queries = (components.queryItems ?? []) + (fragment?.queryItems ?? [])
        func query(_ names: [String]) -> String? {
            queries.first(where: { names.contains($0.name.lowercased()) })?.value
        }

        let rawID: String?
        switch source {
        case .wy:
            guard paths.contains(where: { $0.split(separator: "/").contains("playlist") }) else {
                throw OnlinePlaylistImportError.notPlaylistLink
            }
            rawID = query(["id"])
        case .tx:
            if let explicit = query(["disstid", "dissid"]) {
                rawID = explicit
            } else if let pathID = paths.compactMap({ path -> String? in
                let parts = path.split(separator: "/")
                guard let index = parts.firstIndex(of: "playlist"), index + 1 < parts.count else { return nil }
                return String(parts[index + 1]).replacingOccurrences(of: ".html", with: "")
            }).first {
                rawID = pathID
            } else if paths.contains(where: { $0.contains("/taoge") || $0.split(separator: "/").contains("playlist") }) {
                rawID = query(["id"])
            } else {
                throw OnlinePlaylistImportError.notPlaylistLink
            }
        }
        guard let rawID, let id = normalizedID(rawID) else { throw OnlinePlaylistImportError.notPlaylistLink }
        return OnlinePlaylistReference(source: source, id: id)
    }
}

enum OnlinePlaylistInput: Equatable, Sendable {
    case reference(OnlinePlaylistReference)
    case shortLink(URL)

    static func parse(_ text: String, source: MusicSource) throws -> OnlinePlaylistInput {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 8_192 else { throw OnlinePlaylistImportError.invalidInput }
        if let id = OnlinePlaylistReference.normalizedID(text) {
            return .reference(OnlinePlaylistReference(source: source, id: id))
        }
        let expression = try NSRegularExpression(pattern: "https?://[^\\s<>\"“”]+", options: .caseInsensitive)
        guard let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text),
              var components = URLComponents(string: String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "，。；）)]}"))),
              components.user == nil, components.password == nil, components.port == nil else {
            throw OnlinePlaylistImportError.invalidInput
        }
        components.scheme = "https"
        guard let url = components.url, OnlinePlaylistReference.source(for: url) != nil else {
            throw OnlinePlaylistImportError.unsupportedLink
        }
        if let reference = try? OnlinePlaylistReference.from(url: url) { return .reference(reference) }
        // Only known share redirectors may be resolved; song/homepage links fail immediately.
        let host = url.host?.lowercased()
        if host == "163cn.tv" || host == "u.y.qq.com"
            || (host == "c.y.qq.com" && url.path == "/base/fcgi-bin/u") {
            return .shortLink(url)
        }
        throw OnlinePlaylistImportError.notPlaylistLink
    }
}

public protocol PlaylistShareLinkResolving: Sendable {
    func resolve(_ url: URL) async throws -> URL
}

public struct URLSessionPlaylistShareLinkResolver: PlaylistShareLinkResolving {
    public init() {}

    public func resolve(_ url: URL) async throws -> URL {
        let session = URLSession(configuration: .ephemeral, delegate: PlaylistShareRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        do {
            try Task.checkCancellation()
            let (_, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, (200..<400).contains(response.statusCode),
                  let finalURL = response.url else { throw OnlinePlaylistImportError.unavailable }
            return finalURL
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw SourceError.network(underlying: error)
        }
    }
}

private final class PlaylistShareRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var hops = 0

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        hops += 1
        guard hops <= 8, let url = request.url,
              OnlinePlaylistReference.source(for: url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.port == nil,
              ["http", "https"].contains(components.scheme?.lowercased() ?? "") else {
            completionHandler(nil)
            return
        }
        components.scheme = "https"
        var request = request
        request.url = components.url
        completionHandler(request)
    }
}

public struct OnlinePlaylistPreview: Equatable, Sendable {
    public let reference: OnlinePlaylistReference
    public let name: String
    public let tracks: [Track]
    public let remoteTrackCount: Int
    public let missingTrackCount: Int
    public let invalidTrackCount: Int
    public let duplicateTrackCount: Int

    public var isIncomplete: Bool { missingTrackCount > 0 || invalidTrackCount > 0 }

    public func backupData() throws -> Data {
        try PlaylistBackup.encode(name: name, tracks: tracks)
    }
}

public protocol OnlinePlaylistImporting: Sendable {
    func preview(_ input: String, source: MusicSource) async throws -> OnlinePlaylistPreview
}

/// Reads metadata only. Saving is a separate user action through LibraryStore's atomic backup merge.
public actor OnlinePlaylistImportService: OnlinePlaylistImporting {
    private static let maximumTracks = 5_000
    private let qq: SourceRuntime
    private let chkszAPI: ChkszAPIRequesting
    private let shareLinks: PlaylistShareLinkResolving

    public init(qq: SourceRuntime, chkszAPI: ChkszAPIRequesting,
                shareLinks: PlaylistShareLinkResolving = URLSessionPlaylistShareLinkResolver()) {
        self.qq = qq
        self.chkszAPI = chkszAPI
        self.shareLinks = shareLinks
    }

    public func preview(_ input: String, source: MusicSource) async throws -> OnlinePlaylistPreview {
        try Task.checkCancellation()
        let reference: OnlinePlaylistReference
        switch try OnlinePlaylistInput.parse(input, source: source) {
        case let .reference(value): reference = value
        case let .shortLink(url): reference = try OnlinePlaylistReference.from(url: await shareLinks.resolve(url))
        }
        try Task.checkCancellation()
        switch reference.source {
        case .tx: return try await readQQ(reference)
        case .wy: return try await readNetEase(reference)
        }
    }

    private func readQQ(_ reference: OnlinePlaylistReference) async throws -> OnlinePlaylistPreview {
        var allTracks: [Track] = []
        var page = 1
        var name = ""
        var total = 0
        var pageIDs = Set<[String]>()
        while true {
            try Task.checkCancellation()
            let detail = try await qq.playlistDetail(source: .tx, id: reference.id, page: page)
            try Task.checkCancellation()
            guard detail.source == .tx, detail.page == page, detail.limit > 0, detail.total >= 0,
                  detail.list.allSatisfy({ $0.source == .tx }) else { throw OnlinePlaylistImportError.invalidResponse }
            guard detail.total <= Self.maximumTracks, allTracks.count + detail.list.count <= Self.maximumTracks else {
                throw OnlinePlaylistImportError.tooLarge
            }
            if page == 1 { name = detail.info.name }
            total = max(total, detail.total)
            guard !detail.list.isEmpty, pageIDs.insert(detail.list.map(\.musicID)).inserted else { break }
            allTracks.append(contentsOf: detail.list)
            guard detail.hasMore else { break }
            page += 1
            guard page <= 50 else { throw OnlinePlaylistImportError.tooLarge }
        }
        return try makePreview(reference, name: name, total: total, received: allTracks.count, tracks: allTracks, invalid: 0)
    }

    private func readNetEase(_ reference: OnlinePlaylistReference) async throws -> OnlinePlaylistPreview {
        let data = try await chkszAPI.request(path: "/api/163_playlist", parameters: ["id": reference.id])
        try Task.checkCancellation()
        guard data.count <= PlaylistBackup.maximumFileSize else { throw OnlinePlaylistImportError.tooLarge }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let playlist = object["data"] as? [String: Any],
              let returnedID = Self.string(playlist["id"]),
              OnlinePlaylistReference.normalizedID(returnedID) == reference.id,
              let name = playlist["name"] as? String,
              let songs = playlist["tracks"] as? [Any],
              let total = Self.integer(playlist["trackCount"]), total >= 0 else {
            throw OnlinePlaylistImportError.unavailable
        }
        guard total <= Self.maximumTracks, songs.count <= Self.maximumTracks else { throw OnlinePlaylistImportError.tooLarge }
        let tracks = songs.compactMap { $0 as? [String: Any] }.compactMap { try? Self.netEaseTrack($0) }
        return try makePreview(reference, name: name, total: total, received: songs.count,
                               tracks: tracks, invalid: songs.count - tracks.count)
    }

    private func makePreview(_ reference: OnlinePlaylistReference, name: String, total: Int, received: Int,
                             tracks: [Track], invalid: Int) throws -> OnlinePlaylistPreview {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw OnlinePlaylistImportError.invalidResponse }
        var ids = Set<String>()
        let unique = tracks.filter { ids.insert($0.musicID).inserted }
        // Reuse the backup schema to validate and strip unknown runtime fields before presenting or saving.
        let sanitized = try PlaylistBackup.decode(PlaylistBackup.encode(name: name, tracks: unique)).tracks
        return OnlinePlaylistPreview(reference: reference, name: name, tracks: sanitized,
                                     remoteTrackCount: max(total, received), missingTrackCount: max(0, total - received),
                                     invalidTrackCount: invalid, duplicateTrackCount: tracks.count - unique.count)
    }

    private static func netEaseTrack(_ song: [String: Any]) throws -> Track {
        guard let rawID = string(song["id"]), let id = OnlinePlaylistReference.normalizedID(rawID),
              let name = song["name"] as? String,
              let artists = (song["ar"] ?? song["artists"]) as? [[String: Any]] else {
            throw OnlinePlaylistImportError.invalidResponse
        }
        let artist = artists.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }.joined(separator: "、")
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !artist.isEmpty else {
            throw OnlinePlaylistImportError.invalidResponse
        }
        let album = (song["al"] ?? song["album"]) as? [String: Any] ?? [:]
        var raw: [String: Any] = ["songmid": id, "name": name, "singer": artist, "albumName": album["name"] as? String ?? ""]
        if let milliseconds = integer(song["dt"] ?? song["duration"]), milliseconds > 0 {
            let seconds = milliseconds / 1_000
            raw["interval"] = String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        if let picURL = album["picUrl"] as? String, var components = URLComponents(string: picURL),
           components.host != nil, components.user == nil, components.password == nil,
           ["http", "https"].contains(components.scheme?.lowercased() ?? "") {
            components.scheme = "https"
            raw["img"] = components.url?.absoluteString
        }
        return try Track(source: .wy, raw: raw)
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let number as NSNumber: number.stringValue
        case let string as String: string
        default: nil
        }
    }

    private static func integer(_ value: Any?) -> Int? { string(value).flatMap(Int.init) }
}
