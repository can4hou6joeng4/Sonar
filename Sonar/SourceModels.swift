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
    func playlistCatalog(source: MusicSource, sortId: String, tagId: String?, page: Int) async throws -> PlaylistCatalogPage
    func playlistDetail(source: MusicSource, id: String, page: Int) async throws -> PlaylistDetail
}

public extension SourceRuntime {
    func playlistCatalog(source: MusicSource, sortId: String, tagId: String? = nil, page: Int = 1) async throws -> PlaylistCatalogPage {
        throw SourceError.source(message: "音源运行时不支持歌单广场")
    }

    func playlistDetail(source: MusicSource, id: String, page: Int = 1) async throws -> PlaylistDetail {
        throw SourceError.source(message: "音源运行时不支持歌单详情")
    }
}
