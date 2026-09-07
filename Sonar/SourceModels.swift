import Foundation

public enum MusicSource: String, Codable, Sendable, CaseIterable {
    case wy
    case tx
}

public enum Quality: String, Codable, Sendable, CaseIterable {
    case standard = "128k"
    case high = "320k"
    case lossless = "flac"
    case hiRes = "flac24bit"
}

public struct Track: Codable, Equatable, Sendable {
    public let source: MusicSource
    public let songmid: String
    public let title: String
    public let artist: String
    public let album: String
    public let interval: String?
    public let payload: Data

    public init(source: MusicSource, songmid: String, title: String, artist: String, album: String, interval: String?, payload: Data) {
        self.source = source
        self.songmid = songmid
        self.title = title
        self.artist = artist
        self.album = album
        self.interval = interval
        self.payload = payload
    }

    public init(source: MusicSource, raw: [String: Any]) throws {
        let songmid: String?
        switch raw["songmid"] {
        case let value as String:
            songmid = value
        case let value as NSNumber:
            songmid = value.stringValue
        default:
            songmid = nil
        }
        guard let songmid, !songmid.isEmpty,
              let title = raw["name"] as? String,
              let artist = raw["singer"] as? String else {
            throw SourceError.source(message: "搜索结果缺少曲目信息")
        }
        let album = (raw["albumName"] as? String) ?? ""
        self.init(
            source: source,
            songmid: songmid,
            title: title,
            artist: artist,
            album: album,
            interval: raw["interval"] as? String,
            payload: try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
        )
    }

    public var rawPayload: [String: Any] {
        (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
    }

    public var musicID: String { "\(source.rawValue)_\(songmid)" }

    public var durationSeconds: TimeInterval? {
        guard let interval else { return nil }
        let components = interval.split(separator: ":").compactMap { Double($0) }
        guard !components.isEmpty else { return nil }
        return components.reversed().enumerated().reduce(0) { result, item in
            result + item.element * pow(60, Double(item.offset))
        }
    }
}

public struct SearchPage: Codable, Sendable {
    public let list: [Track]
    public let total: Int
    public let allPage: Int

    public init(list: [Track], total: Int, allPage: Int) {
        self.list = list
        self.total = total
        self.allPage = allPage
    }
}

public struct ArtistSummary: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let source: MusicSource
    public let name: String
    public let imageURL: String?
    public let songCount: Int?
    public let albumCount: Int?

    public init(id: String, source: MusicSource, name: String, imageURL: String?, songCount: Int?, albumCount: Int?) throws {
        let cleanID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty, !cleanName.isEmpty else {
            throw SourceError.source(message: "歌手结果缺少身份信息")
        }
        self.id = cleanID
        self.source = source
        self.name = cleanName
        self.imageURL = try SourceArtworkURL.normalizedString(imageURL)
        self.songCount = Self.normalizedCount(songCount)
        self.albumCount = Self.normalizedCount(albumCount)
    }

    public var stableID: String { "\(source.rawValue)_artist_\(id)" }

    private static func normalizedCount(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }
}

public struct ArtistSearchPage: Sendable {
    public let list: [ArtistSummary]
    public let total: Int
    public let source: MusicSource
    public let page: Int
    public let limit: Int
    public let hasMore: Bool

    public init(
        list: [ArtistSummary],
        total: Int,
        source: MusicSource,
        page: Int = 1,
        limit: Int = 0,
        hasMore: Bool? = nil
    ) {
        let normalizedPage = max(1, page)
        let normalizedLimit = max(1, limit > 0 ? limit : list.count)
        let normalizedTotal = max(max(0, total), list.count)

        self.list = list
        self.total = normalizedTotal
        self.source = source
        self.page = normalizedPage
        self.limit = normalizedLimit
        self.hasMore = !list.isEmpty && (hasMore ?? (normalizedPage * normalizedLimit < normalizedTotal))
    }
}

public struct AlbumSummary: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let source: MusicSource
    public let name: String
    public let artist: String
    public let imageURL: String?
    public let releaseDate: String?
    public let trackCount: Int?

    public init(id: String, source: MusicSource, name: String, artist: String, imageURL: String?, releaseDate: String?, trackCount: Int?) throws {
        let cleanID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty, !cleanName.isEmpty else {
            throw SourceError.source(message: "专辑结果缺少身份信息")
        }
        self.id = cleanID
        self.source = source
        self.name = cleanName
        self.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        self.imageURL = try SourceArtworkURL.normalizedString(imageURL)
        self.releaseDate = SourceReleaseDate.normalizedString(releaseDate)
        self.trackCount = Self.normalizedCount(trackCount)
    }

    public var stableID: String { "\(source.rawValue)_album_\(id)" }

    private static func normalizedCount(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }
}

public struct AlbumPage: Sendable {
    public let list: [AlbumSummary]
    public let total: Int
    public let source: MusicSource
}

public struct AlbumDetail: Sendable {
    public let album: AlbumSummary
    public let tracks: [Track]
}

private enum SourceArtworkURL {
    static func normalizedString(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            throw SourceError.source(message: "音源返回封面地址异常")
        }
        if scheme == "http" { components.scheme = "https" }
        guard let normalized = components.url?.absoluteString else {
            throw SourceError.source(message: "音源返回封面地址异常")
        }
        return normalized
    }
}

private enum SourceReleaseDate {
    private static let leadingDate = try! NSRegularExpression(
        pattern: #"^(\d{4})[-./年](\d{1,2})[-./月](\d{1,2})"#
    )

    static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = leadingDate.firstMatch(in: trimmed, range: range),
              let yearRange = Range(match.range(at: 1), in: trimmed),
              let monthRange = Range(match.range(at: 2), in: trimmed),
              let dayRange = Range(match.range(at: 3), in: trimmed),
              let year = Int(trimmed[yearRange]),
              let month = Int(trimmed[monthRange]),
              let day = Int(trimmed[dayRange]) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        let validated = calendar.dateComponents([.year, .month, .day], from: date)
        guard validated.year == year, validated.month == month, validated.day == day else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

public struct PlaylistCategory: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public extension MusicSource {
    var playlistCategories: [PlaylistCategory] {
        switch self {
        case .wy:
            return [PlaylistCategory(id: "hot", name: "推荐")]
        case .tx:
            return [
                PlaylistCategory(id: "5", name: "最热"),
                PlaylistCategory(id: "2", name: "最新"),
            ]
        }
    }

    var displayName: String {
        switch self {
        case .wy: "网易云"
        case .tx: "QQ"
        }
    }
}

public struct PlaylistSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let img: String?
    public let author: String
    public let playCount: String
    public let total: Int?
    public let desc: String?
    public let time: String?
    public let source: MusicSource

    public init(
        id: String,
        name: String,
        img: String?,
        author: String,
        playCount: String,
        total: Int?,
        desc: String?,
        time: String?,
        source: MusicSource
    ) {
        self.id = id
        self.name = name
        self.img = img
        self.author = author
        self.playCount = playCount
        self.total = total
        self.desc = desc
        self.time = time
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, img, author, total, desc, time, source
        case playCount = "play_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .id) {
            id = value
        } else if let value = try? container.decode(Int.self, forKey: .id) {
            id = String(value)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "歌单缺少有效 ID")
        }
        name = try container.decode(String.self, forKey: .name)
        img = try container.decodeIfPresent(String.self, forKey: .img)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        playCount = try container.decodeIfPresent(String.self, forKey: .playCount) ?? ""
        total = try container.decodeIfPresent(Int.self, forKey: .total)
        desc = try container.decodeIfPresent(String.self, forKey: .desc)
        time = try container.decodeIfPresent(String.self, forKey: .time)
        source = try container.decode(MusicSource.self, forKey: .source)
    }
}

public struct PlaylistCatalogPage: Codable, Equatable, Sendable {
    public let list: [PlaylistSummary]
    public let total: Int
    public let page: Int
    public let limit: Int
    public let source: MusicSource

    public init(list: [PlaylistSummary], total: Int, page: Int, limit: Int, source: MusicSource) {
        self.list = list
        self.total = total
        self.page = page
        self.limit = limit
        self.source = source
    }
}

public struct PlaylistDetailInfo: Codable, Equatable, Sendable {
    public let name: String
    public let img: String?
    public let desc: String?
    public let author: String
    public let playCount: String

    private enum CodingKeys: String, CodingKey {
        case name, img, desc, author
        case playCount = "play_count"
    }
}

public struct PlaylistDetail: Sendable {
    public let list: [Track]
    public let total: Int
    public let page: Int
    public let limit: Int
    public let source: MusicSource
    public let info: PlaylistDetailInfo

    public init(list: [Track], total: Int, page: Int, limit: Int, source: MusicSource, info: PlaylistDetailInfo) {
        self.list = list
        self.total = total
        self.page = page
        self.limit = limit
        self.source = source
        self.info = info
    }

    public var supportsPagination: Bool { source == .wy }
    public var hasMore: Bool { supportsPagination && page * limit < total && !list.isEmpty }
}

public struct LyricInfo: Codable, Sendable, Equatable {
    public let lyric: String
    public let tlyric: String?
    public let rlyric: String?
    public let lxlyric: String?
}

public enum SourceError: Error, LocalizedError, Sendable {
    case network(underlying: Error)
    case source(message: String)
    case credentialRequired(hint: String)

    public var errorDescription: String? {
        switch self {
        case .network:
            return "网络失败"
        case let .source(message):
            return message
        case let .credentialRequired(hint):
            return hint
        }
    }
}

public protocol SourceRuntime: Sendable {
    func search(_ keyword: String, source: MusicSource, page: Int) async throws -> SearchPage
    func lyric(_ track: Track) async throws -> LyricInfo
    func picURL(_ track: Track) async throws -> URL
    func tipSearch(_ keyword: String) async throws -> [String]
    func hotSearch(source: MusicSource) async throws -> [String]
    func playlistCatalog(source: MusicSource, sortId: String, tagId: String?, page: Int) async throws -> PlaylistCatalogPage
    func playlistDetail(source: MusicSource, id: String, page: Int) async throws -> PlaylistDetail
    func searchArtists(_ keyword: String, source: MusicSource, page: Int) async throws -> ArtistSearchPage
    func searchArtists(_ keyword: String, source: MusicSource, page: Int, limit: Int) async throws -> ArtistSearchPage
    func artistPopularTracks(_ artist: ArtistSummary) async throws -> [Track]
    func artistAlbums(_ artist: ArtistSummary, page: Int) async throws -> AlbumPage
    func albumTracks(_ album: AlbumSummary) async throws -> AlbumDetail
    func trackDetail(_ track: Track) async throws -> Track
}

public extension SourceRuntime {
    func trackDetail(_ track: Track) async throws -> Track {
        track
    }

    func hotSearch(source: MusicSource) async throws -> [String] {
        throw SourceError.source(message: "音源运行时不支持热门搜索")
    }

    func playlistCatalog(source: MusicSource, sortId: String, tagId: String? = nil, page: Int = 1) async throws -> PlaylistCatalogPage {
        throw SourceError.source(message: "音源运行时不支持歌单广场")
    }

    func playlistDetail(source: MusicSource, id: String, page: Int = 1) async throws -> PlaylistDetail {
        throw SourceError.source(message: "音源运行时不支持歌单详情")
    }

    func searchArtists(_ keyword: String, source: MusicSource, page: Int = 1) async throws -> ArtistSearchPage {
        ArtistSearchPage(list: [], total: 0, source: source)
    }

    func searchArtists(_ keyword: String, source: MusicSource, page: Int, limit: Int) async throws -> ArtistSearchPage {
        try await searchArtists(keyword, source: source, page: page)
    }

    func artistPopularTracks(_ artist: ArtistSummary) async throws -> [Track] {
        throw SourceError.source(message: "音源运行时不支持歌手热门歌曲")
    }

    func artistAlbums(_ artist: ArtistSummary, page: Int = 1) async throws -> AlbumPage {
        throw SourceError.source(message: "音源运行时不支持歌手专辑")
    }

    func albumTracks(_ album: AlbumSummary) async throws -> AlbumDetail {
        throw SourceError.source(message: "音源运行时不支持专辑曲目")
    }
}
