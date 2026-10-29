import Foundation
import CoreFoundation

public enum PlaylistBackupError: Error, LocalizedError, Equatable {
    case invalidFile
    case unsupportedVersion
    case tooLarge
    case invalidTrack
    case pendingChanges
    case saveFailed

    public var errorDescription: String? {
        switch self {
        case .invalidFile: return "无法读取歌单备份，请选择 Sonar 导出的 JSON 文件"
        case .unsupportedVersion: return "此备份版本暂不支持，请更新 Sonar 后再试"
        case .tooLarge: return "备份文件过大，请选择不超过 10 MB 的歌单备份"
        case .invalidTrack: return "备份包含不完整或无效的歌曲信息，未导入任何歌曲"
        case .pendingChanges: return "歌单还有未保存的更改，请稍后重试导入"
        case .saveFailed: return "歌单保存失败，已撤销此次导入，请稍后重试"
        }
    }
}

public struct PlaylistImportResult: Equatable, Sendable {
    public let insertedCount: Int
    public let skippedCount: Int
    public let totalCount: Int
    public let playlistName: String
}

/// Portable metadata only. Never serialize Track.payload, playback URLs or runtime credentials.
public enum PlaylistBackup {
    public static let maximumFileSize = 10 * 1024 * 1024
    private static let maximumTracks = 50_000

    private struct Document: Codable {
        let format: String
        let version: Int
        let name: String
        let tracks: [Entry]
    }

    private struct Entry: Codable {
        let source: MusicSource
        let songmid: String
        let title: String
        let artist: String
        let album: String
        let interval: String?
        let metadata: Metadata
    }

    private struct Metadata: Codable {
        let strMediaMid: String?
        let songId: Identifier?
        let albumId: Identifier?
        let albumMid: String?
        let img: String?
        let types: [QualityDescriptor]?
        let _types: [String: QualitySize]?
    }

    private struct QualityDescriptor: Codable {
        let type: Quality
        let size: String?
    }

    private struct QualitySize: Codable {
        let size: String?
    }

    private enum Identifier: Codable {
        case string(String)
        case number(Int64)

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let number = try? value.decode(Int64.self) { self = .number(number) }
            else { self = .string(try value.decode(String.self)) }
        }

        init?(_ value: Any?) {
            if let string = value as? String { self = .string(string) }
            else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                guard number.doubleValue.isFinite, number.doubleValue == Double(number.int64Value) else { return nil }
                self = .number(number.int64Value)
            } else { return nil }
        }

        func encode(to encoder: Encoder) throws {
            var value = encoder.singleValueContainer()
            switch self {
            case .string(let string): try value.encode(string)
            case .number(let number): try value.encode(number)
            }
        }

        var raw: Any {
            switch self {
            case .string(let string): return string
            case .number(let number): return number
            }
        }

        func validate() throws {
            switch self {
            case .string(let string): try PlaylistBackup.validateIdentifier(string, allowEmpty: true)
            case .number(let number): guard number >= 0 else { throw PlaylistBackupError.invalidTrack }
            }
        }
    }

    static func encode(name: String, tracks: [Track]) throws -> Data {
        let entries = try tracks.map { track in
            let raw = track.rawPayload
            let types = (raw["types"] as? [[String: Any]])?.compactMap { value -> QualityDescriptor? in
                guard let rawType = value["type"] as? String, let type = Quality(rawValue: rawType) else { return nil }
                return QualityDescriptor(type: type, size: value["size"] as? String)
            }
            var typeMap: [String: QualitySize] = [:]
            for (key, value) in raw["_types"] as? [String: Any] ?? [:] where Quality(rawValue: key) != nil {
                guard let value = value as? [String: Any] else { continue }
                typeMap[key] = QualitySize(size: value["size"] as? String)
            }
            let metadata = Metadata(
                strMediaMid: raw["strMediaMid"] as? String,
                songId: Identifier(raw["songId"]),
                albumId: Identifier(raw["albumId"]),
                albumMid: raw["albumMid"] as? String,
                img: try cleanArtwork(raw["img"] as? String),
                types: types,
                _types: typeMap.isEmpty ? nil : typeMap
            )
            return Entry(source: track.source, songmid: track.songmid, title: track.title,
                         artist: track.artist, album: track.album, interval: track.interval, metadata: metadata)
        }
        let document = Document(format: "sonar.personal-playlist", version: 1, name: name, tracks: entries)
        _ = try validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard data.count <= maximumFileSize else { throw PlaylistBackupError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> (name: String, tracks: [Track]) {
        guard data.count <= maximumFileSize else { throw PlaylistBackupError.tooLarge }
        // Read the version independently so a future entry shape still yields an actionable version error.
        struct Header: Decodable { let format: String; let version: Int }
        do {
            let header = try JSONDecoder().decode(Header.self, from: data)
            guard header.format == "sonar.personal-playlist" else { throw PlaylistBackupError.invalidFile }
            guard header.version == 1 else { throw PlaylistBackupError.unsupportedVersion }
            return try validate(JSONDecoder().decode(Document.self, from: data))
        } catch let error as PlaylistBackupError { throw error }
        catch { throw PlaylistBackupError.invalidFile }
    }

    private static func validate(_ document: Document) throws -> (name: String, tracks: [Track]) {
        let name = document.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 512 else { throw PlaylistBackupError.invalidFile }
        guard document.tracks.count <= maximumTracks else { throw PlaylistBackupError.tooLarge }
        let tracks = try document.tracks.map { entry in
            try validateIdentifier(entry.songmid)
            guard !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.title.count <= 2048, entry.artist.count <= 2048, entry.album.count <= 2048,
                  (entry.interval?.count ?? 0) <= 32 else { throw PlaylistBackupError.invalidTrack }
            if let interval = entry.interval, !interval.isEmpty {
                let parts = interval.split(separator: ":", omittingEmptySubsequences: false)
                guard (1...3).contains(parts.count), parts.allSatisfy({ part in
                    !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) }
                }) else { throw PlaylistBackupError.invalidTrack }
            }
            let metadata = entry.metadata
            if let value = metadata.strMediaMid { try validateIdentifier(value, allowEmpty: true) }
            if let value = metadata.albumMid { try validateIdentifier(value, allowEmpty: true) }
            try metadata.songId?.validate()
            try metadata.albumId?.validate()
            guard (metadata.types?.count ?? 0) <= Quality.allCases.count,
                  (metadata._types?.count ?? 0) <= Quality.allCases.count else { throw PlaylistBackupError.invalidTrack }
            var raw: [String: Any] = [
                "source": entry.source.rawValue, "songmid": entry.songmid, "name": entry.title,
                "singer": entry.artist, "albumName": entry.album,
            ]
            raw["interval"] = entry.interval
            raw["strMediaMid"] = metadata.strMediaMid
            raw["songId"] = metadata.songId?.raw
            raw["albumId"] = metadata.albumId?.raw
            raw["albumMid"] = metadata.albumMid
            raw["img"] = try cleanArtwork(metadata.img)
            if let types = metadata.types {
                raw["types"] = try types.map { descriptor -> [String: Any] in
                    try validateSize(descriptor.size)
                    return ["type": descriptor.type.rawValue, "size": descriptor.size as Any? ?? NSNull()]
                }
            }
            if let typeMap = metadata._types {
                var values: [String: Any] = [:]
                for (key, value) in typeMap {
                    guard Quality(rawValue: key) != nil else { throw PlaylistBackupError.invalidTrack }
                    try validateSize(value.size)
                    values[key] = ["size": value.size as Any? ?? NSNull()]
                }
                raw["_types"] = values
            }
            return try Track(source: entry.source, raw: raw)
        }
        return (name, tracks)
    }

    private static func validateIdentifier(_ value: String, allowEmpty: Bool = false) throws {
        guard value.count <= 256, allowEmpty || !value.isEmpty,
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_-".unicodeScalars.contains($0) }) else {
            throw PlaylistBackupError.invalidTrack
        }
    }

    private static func validateSize(_ value: String?) throws {
        guard (value?.count ?? 0) <= 64 else { throw PlaylistBackupError.invalidTrack }
    }

    private static func cleanArtwork(_ value: String?) throws -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard value.count <= 4096,
              var components = URLComponents(string: value),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              !(components.host ?? "").isEmpty,
              components.user == nil, components.password == nil else { throw PlaylistBackupError.invalidTrack }
        components.scheme = "https"
        // Album covers can be fetched again; signed query/fragment credentials must not leave the device.
        components.query = nil
        components.fragment = nil
        return components.string
    }
}
