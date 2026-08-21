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
}
