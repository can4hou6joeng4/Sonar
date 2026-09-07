import Foundation
import SwiftData

public enum PlaylistKind: String, CaseIterable, Identifiable, Sendable {
    case music
    case video

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .music: "音乐歌单"
        case .video: "视频歌单"
        }
    }
}

public struct PlaylistMetadata: Equatable, Sendable {
    public var kind: PlaylistKind
    public var isShared: Bool
    public var isPrivate: Bool

    public init(kind: PlaylistKind = .music, isShared: Bool = false, isPrivate: Bool = false) {
        self.kind = kind
        self.isShared = isShared
        self.isPrivate = isPrivate
    }
}

public enum SonarSchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [Playlist.self, PlaylistItem.self, TrackRecord.self]
    }

    @Model
    public final class Playlist {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var sortIndex: Int
        public var isSystem: Bool
        @Relationship(deleteRule: .cascade, inverse: \PlaylistItem.playlist)
        public var items: [PlaylistItem]

        public init(id: UUID = UUID(), name: String, sortIndex: Int, isSystem: Bool = false, items: [PlaylistItem] = []) {
            self.id = id
            self.name = name
            self.sortIndex = sortIndex
            self.isSystem = isSystem
            self.items = items
        }
    }

    @Model
    public final class PlaylistItem {
        public var sortIndex: Int
        public var playlist: Playlist?
        public var track: TrackRecord

        public init(sortIndex: Int, playlist: Playlist? = nil, track: TrackRecord) {
            self.sortIndex = sortIndex
            self.playlist = playlist
            self.track = track
        }
    }

    @Model
    public final class TrackRecord {
        @Attribute(.unique) public var musicId: String
        public var title: String
        public var artist: String
        public var album: String
        public var duration: Int
        public var source: String
        public var payload: Data

        public init(musicId: String, title: String, artist: String, album: String, duration: Int, source: String, payload: Data) {
            self.musicId = musicId
            self.title = title
            self.artist = artist
            self.album = album
            self.duration = duration
            self.source = source
            self.payload = payload
        }
    }
}

public enum SonarSchemaV2: VersionedSchema {
    public static var versionIdentifier = Schema.Version(2, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [Playlist.self, PlaylistItem.self, TrackRecord.self]
    }

    @Model
    public final class Playlist {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var sortIndex: Int
        public var isSystem: Bool
        @Relationship(deleteRule: .cascade, inverse: \PlaylistItem.playlist)
        public var items: [PlaylistItem]

        public init(id: UUID = UUID(), name: String, sortIndex: Int, isSystem: Bool = false, items: [PlaylistItem] = []) {
            self.id = id
            self.name = name
            self.sortIndex = sortIndex
            self.isSystem = isSystem
            self.items = items
        }
    }

    @Model
    public final class PlaylistItem {
        public var sortIndex: Int
        public var playlist: Playlist?
        public var track: TrackRecord

        public init(sortIndex: Int, playlist: Playlist? = nil, track: TrackRecord) {
            self.sortIndex = sortIndex
            self.playlist = playlist
            self.track = track
        }
    }

    @Model
    public final class TrackRecord {
        @Attribute(.unique) public var musicId: String
        public var title: String
        public var artist: String
        public var album: String
        public var duration: Int
        public var source: String
        public var payload: Data
        public var accentHex: String?

        public init(musicId: String, title: String, artist: String, album: String, duration: Int, source: String, payload: Data, accentHex: String? = nil) {
            self.musicId = musicId
            self.title = title
            self.artist = artist
            self.album = album
            self.duration = duration
            self.source = source
            self.payload = payload
            self.accentHex = accentHex
        }
    }
}

public enum SonarSchemaV3: VersionedSchema {
    public static var versionIdentifier = Schema.Version(3, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [Playlist.self, PlaylistItem.self, TrackRecord.self]
    }

    @Model
    public final class Playlist {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var sortIndex: Int
        public var isSystem: Bool
        public var kindRaw: String = PlaylistKind.music.rawValue
        public var isShared: Bool = false
        public var isPrivate: Bool = false
        @Relationship(deleteRule: .cascade, inverse: \PlaylistItem.playlist)
        public var items: [PlaylistItem]

        public init(
            id: UUID = UUID(),
            name: String,
            sortIndex: Int,
            isSystem: Bool = false,
            kindRaw: String = PlaylistKind.music.rawValue,
            isShared: Bool = false,
            isPrivate: Bool = false,
            items: [PlaylistItem] = []
        ) {
            self.id = id
            self.name = name
            self.sortIndex = sortIndex
            self.isSystem = isSystem
            self.kindRaw = kindRaw
            self.isShared = isShared
            self.isPrivate = isPrivate
            self.items = items
        }
    }

    @Model
    public final class PlaylistItem {
        public var sortIndex: Int
        public var playlist: Playlist?
        public var track: TrackRecord

        public init(sortIndex: Int, playlist: Playlist? = nil, track: TrackRecord) {
            self.sortIndex = sortIndex
            self.playlist = playlist
            self.track = track
        }
    }

    @Model
    public final class TrackRecord {
        @Attribute(.unique) public var musicId: String
        public var title: String
        public var artist: String
        public var album: String
        public var duration: Int
        public var source: String
        public var payload: Data
        public var accentHex: String?

        public init(musicId: String, title: String, artist: String, album: String, duration: Int, source: String, payload: Data, accentHex: String? = nil) {
            self.musicId = musicId
            self.title = title
            self.artist = artist
            self.album = album
            self.duration = duration
            self.source = source
            self.payload = payload
            self.accentHex = accentHex
        }
    }
}

public enum SonarSchemaV4: VersionedSchema {
    public static var versionIdentifier = Schema.Version(4, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [Playlist.self, PlaylistItem.self, TrackRecord.self]
    }

    @Model
    public final class Playlist {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var sortIndex: Int
        public var isSystem: Bool
        public var kindRaw: String = PlaylistKind.music.rawValue
        public var isShared: Bool = false
        public var isPrivate: Bool = false
        public var isPrimaryPersonal: Bool = false
        public var isArchived: Bool = false
        @Relationship(deleteRule: .cascade, inverse: \PlaylistItem.playlist)
        public var items: [PlaylistItem]

        public init(
            id: UUID = UUID(),
            name: String,
            sortIndex: Int,
            isSystem: Bool = false,
            kindRaw: String = PlaylistKind.music.rawValue,
            isShared: Bool = false,
            isPrivate: Bool = false,
            isPrimaryPersonal: Bool = false,
            isArchived: Bool = false,
            items: [PlaylistItem] = []
        ) {
            self.id = id
            self.name = name
            self.sortIndex = sortIndex
            self.isSystem = isSystem
            self.kindRaw = kindRaw
            self.isShared = isShared
            self.isPrivate = isPrivate
            self.isPrimaryPersonal = isPrimaryPersonal
            self.isArchived = isArchived
            self.items = items
        }
    }

    @Model
    public final class PlaylistItem {
        public var sortIndex: Int
        public var playlist: Playlist?
        public var track: TrackRecord

        public init(sortIndex: Int, playlist: Playlist? = nil, track: TrackRecord) {
            self.sortIndex = sortIndex
            self.playlist = playlist
            self.track = track
        }
    }

    @Model
    public final class TrackRecord {
        @Attribute(.unique) public var musicId: String
        public var title: String
        public var artist: String
        public var album: String
        public var duration: Int
        public var source: String
        public var payload: Data
        public var accentHex: String?

        public init(musicId: String, title: String, artist: String, album: String, duration: Int, source: String, payload: Data, accentHex: String? = nil) {
            self.musicId = musicId
            self.title = title
            self.artist = artist
            self.album = album
            self.duration = duration
            self.source = source
            self.payload = payload
            self.accentHex = accentHex
        }
    }
}

public enum SonarMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SonarSchemaV1.self, SonarSchemaV2.self, SonarSchemaV3.self, SonarSchemaV4.self]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SonarSchemaV1.self, toVersion: SonarSchemaV2.self),
            .lightweight(fromVersion: SonarSchemaV2.self, toVersion: SonarSchemaV3.self),
            .lightweight(fromVersion: SonarSchemaV3.self, toVersion: SonarSchemaV4.self),
        ]
    }
}

public typealias Playlist = SonarSchemaV4.Playlist
public typealias PlaylistItem = SonarSchemaV4.PlaylistItem
public typealias TrackRecord = SonarSchemaV4.TrackRecord

public enum SonarModelContainer {
    public static func make(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SonarSchemaV4.self)
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration("Sonar", schema: schema, url: url, cloudKitDatabase: .none)
        } else if inMemory {
            configuration = ModelConfiguration("Sonar", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let storeURL = directory.appendingPathComponent("Sonar.store")
            configuration = ModelConfiguration("Sonar", schema: schema, url: storeURL, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: SonarMigrationPlan.self, configurations: [configuration])
    }
}

extension Playlist {
    public var kind: PlaylistKind {
        get { PlaylistKind(rawValue: kindRaw) ?? .music }
        set { kindRaw = newValue.rawValue }
    }

    public var orderedItems: [PlaylistItem] {
        items.sorted { lhs, rhs in
            lhs.sortIndex == rhs.sortIndex
                ? lhs.track.musicId < rhs.track.musicId
                : lhs.sortIndex < rhs.sortIndex
        }
    }
}

extension TrackRecord {
    public convenience init(track: Track, accentHex: String? = nil) {
        self.init(
            musicId: track.musicID,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: Int(track.durationSeconds ?? 0),
            source: track.source.rawValue,
            payload: track.payload,
            accentHex: accentHex
        )
    }

    public func update(from track: Track) {
        title = track.title
        artist = track.artist
        album = track.album
        duration = Int(track.durationSeconds ?? 0)
        source = track.source.rawValue
        payload = track.payload
    }

    public var track: Track? {
        guard let source = MusicSource(rawValue: source) else { return nil }
        let prefix = "\(source.rawValue)_"
        guard musicId.hasPrefix(prefix) else { return nil }
        let songmid = String(musicId.dropFirst(prefix.count))
        guard !songmid.isEmpty else { return nil }
        return Track(
            source: source,
            songmid: songmid,
            title: title,
            artist: artist,
            album: album,
            interval: Self.interval(from: duration),
            payload: payload
        )
    }

    private static func interval(from duration: Int) -> String? {
        guard duration > 0 else { return nil }
        return String(format: "%02d:%02d", duration / 60, duration % 60)
    }
}
