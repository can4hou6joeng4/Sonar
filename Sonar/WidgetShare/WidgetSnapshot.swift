import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

public enum PersonalPlaylistDefaults {
    public static let name = "can4hou6joeng4"
    public static let legacyNames: Set<String> = ["我喜欢的音乐"]
}

public struct WidgetPlaybackSnapshot: Codable, Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let quality: String
    public let isPlaying: Bool
    public let hasTrack: Bool
    public let favoritesCount: Int
    public let updatedAt: Date

    public init(
        title: String = "",
        artist: String = "",
        album: String = "",
        quality: String = "",
        isPlaying: Bool = false,
        hasTrack: Bool = false,
        favoritesCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.quality = quality
        self.isPlaying = isPlaying
        self.hasTrack = hasTrack
        self.favoritesCount = favoritesCount
        self.updatedAt = updatedAt
    }

    public static let empty = WidgetPlaybackSnapshot(
        title: "暂无播放",
        artist: "点按开启随心听",
        album: "",
        quality: "",
        isPlaying: false,
        hasTrack: false,
        favoritesCount: 0,
        updatedAt: Date()
    )
}

public final class WidgetShareStore: @unchecked Sendable {
    public static let shared = WidgetShareStore()
    public static let defaultAppGroupIdentifier = "group.cn.bobochang.sonar"
    public static var appGroupIdentifier: String {
        shared.resolvedAppGroupIdentifier
    }
    private static let snapshotKey = "sonar.widget.playback_snapshot"
    private static let artworkFileName = "current_artwork.jpg"
    private static let snapshotJSONFileName = "playback_snapshot.json"

    public enum DarwinNotification {
        public static let togglePlay = "cn.bobochang.sonar.remote.togglePlay"
        public static let nextTrack = "cn.bobochang.sonar.remote.next"
        public static let previousTrack = "cn.bobochang.sonar.remote.previous"
        public static let play = "cn.bobochang.sonar.remote.play"
        public static let pause = "cn.bobochang.sonar.remote.pause"
        public static let widgetReload = "cn.bobochang.sonar.remote.reload"
    }

    private let customDefaults: UserDefaults?
    private let customContainerURL: URL?
    private let useSharedLocations: Bool
    private let lock = NSLock()
    private var lastSavedSnapshot: WidgetPlaybackSnapshot?

    public init(defaults: UserDefaults? = nil, containerURL: URL? = nil) {
        self.customDefaults = defaults
        self.customContainerURL = containerURL
        self.useSharedLocations = (defaults == nil && containerURL == nil)
    }

    /// Dynamically resolves the active App Group identifier by checking the default identifier,
    /// inspecting embedded.mobileprovision for provisioned application-groups,
    /// and testing which one actually returns a non-nil container URL.
    public lazy var resolvedAppGroupIdentifier: String = {
        if !useSharedLocations { return Self.defaultAppGroupIdentifier }

        // 1. Try default identifier
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.defaultAppGroupIdentifier) != nil {
            return Self.defaultAppGroupIdentifier
        }

        // 2. Check embedded.mobileprovision for dynamically provisioned groups (e.g. group.<TeamID>.cn.bobochang.sonar)
        if let provisionURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: provisionURL),
           let content = String(data: data, encoding: .ascii) {
            if let startRange = content.range(of: "<key>com.apple.security.application-groups</key>") {
                let after = content[startRange.upperBound...]
                var searchRange = after.startIndex..<after.endIndex
                while let stringStart = after[searchRange].range(of: "<string>"),
                      let stringEnd = after[stringStart.upperBound...searchRange.upperBound].range(of: "</string>") {
                    let groupID = String(after[stringStart.upperBound..<stringEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !groupID.isEmpty,
                       FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil {
                        return groupID
                    }
                    searchRange = stringEnd.upperBound..<searchRange.upperBound
                }
            }
        }

        // 3. Check group.<bundleID>
        if let bundleID = Bundle.main.bundleIdentifier {
            let baseID = bundleID.hasSuffix(".widget") ? String(bundleID.dropLast(7)) : bundleID
            let candidate = "group." + baseID
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: candidate) != nil {
                return candidate
            }
        }

        return Self.defaultAppGroupIdentifier
    }()

    public var userDefaults: UserDefaults? {
        if !useSharedLocations { return customDefaults }
        return UserDefaults(suiteName: resolvedAppGroupIdentifier) ?? UserDefaults.standard
    }

    public var containerURL: URL? {
        if !useSharedLocations { return customContainerURL }
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: resolvedAppGroupIdentifier) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    public func saveSnapshot(_ snapshot: WidgetPlaybackSnapshot, reloadWidgets: Bool = true) {
        lock.lock()
        if let last = lastSavedSnapshot,
           last.title == snapshot.title,
           last.artist == snapshot.artist,
           last.album == snapshot.album,
           last.quality == snapshot.quality,
           last.isPlaying == snapshot.isPlaying,
           last.hasTrack == snapshot.hasTrack,
           last.favoritesCount == snapshot.favoritesCount {
            lock.unlock()
            return
        }
        lastSavedSnapshot = snapshot
        lock.unlock()

        // 1. Write JSON file to shared container
        if let data = try? JSONEncoder().encode(snapshot), let containerURL {
            try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
            let jsonURL = containerURL.appendingPathComponent(Self.snapshotJSONFileName)
            try? data.write(to: jsonURL, options: .atomic)
        }

        // 2. Write to UserDefaults (both encoded JSON and direct primitives for maximum cross-process compatibility)
        if let defaults = userDefaults {
            if let data = try? JSONEncoder().encode(snapshot) {
                defaults.set(data, forKey: Self.snapshotKey)
            }
            defaults.set(snapshot.title, forKey: "sonar.widget.title")
            defaults.set(snapshot.artist, forKey: "sonar.widget.artist")
            defaults.set(snapshot.album, forKey: "sonar.widget.album")
            defaults.set(snapshot.quality, forKey: "sonar.widget.quality")
            defaults.set(snapshot.isPlaying, forKey: "sonar.widget.isPlaying")
            defaults.set(snapshot.hasTrack, forKey: "sonar.widget.hasTrack")
            defaults.set(snapshot.favoritesCount, forKey: "sonar.widget.favoritesCount")
            defaults.set(snapshot.updatedAt.timeIntervalSince1970, forKey: "sonar.widget.updatedAt")
            defaults.synchronize()
        }

        if reloadWidgets {
            reloadAllWidgets()
        }
    }

    public func loadSnapshot() -> WidgetPlaybackSnapshot {
        // 1. Try reading from container JSON file
        if let containerURL {
            let jsonURL = containerURL.appendingPathComponent(Self.snapshotJSONFileName)
            if let data = try? Data(contentsOf: jsonURL),
               let snapshot = try? JSONDecoder().decode(WidgetPlaybackSnapshot.self, from: data) {
                return snapshot
            }
        }

        // 2. Try reading from UserDefaults JSON data
        if let data = userDefaults?.data(forKey: Self.snapshotKey),
           let snapshot = try? JSONDecoder().decode(WidgetPlaybackSnapshot.self, from: data) {
            return snapshot
        }

        // 3. Fallback: read from direct UserDefaults primitive keys
        if let defaults = userDefaults,
           let hasTrack = defaults.object(forKey: "sonar.widget.hasTrack") as? Bool,
           hasTrack {
            let title = defaults.string(forKey: "sonar.widget.title") ?? ""
            let artist = defaults.string(forKey: "sonar.widget.artist") ?? ""
            let album = defaults.string(forKey: "sonar.widget.album") ?? ""
            let quality = defaults.string(forKey: "sonar.widget.quality") ?? ""
            let isPlaying = defaults.bool(forKey: "sonar.widget.isPlaying")
            let favoritesCount = defaults.integer(forKey: "sonar.widget.favoritesCount")
            let timestamp = defaults.double(forKey: "sonar.widget.updatedAt")
            let updatedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date()
            return WidgetPlaybackSnapshot(
                title: title,
                artist: artist,
                album: album,
                quality: quality,
                isPlaying: isPlaying,
                hasTrack: hasTrack,
                favoritesCount: favoritesCount,
                updatedAt: updatedAt
            )
        }

        return .empty
    }

    public func updateFavoritesCount(_ count: Int) {
        let current = loadSnapshot()
        let updated = WidgetPlaybackSnapshot(
            title: current.title,
            artist: current.artist,
            album: current.album,
            quality: current.quality,
            isPlaying: current.isPlaying,
            hasTrack: current.hasTrack,
            favoritesCount: count,
            updatedAt: Date()
        )
        saveSnapshot(updated)
    }

    public func saveArtwork(_ data: Data) {
        guard let containerURL else { return }
        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        let fileURL = containerURL.appendingPathComponent(Self.artworkFileName)
        try? data.write(to: fileURL, options: .atomic)
    }

    public func artworkFileURL() -> URL? {
        guard let containerURL else { return nil }
        let fileURL = containerURL.appendingPathComponent(Self.artworkFileName)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    public func clearArtwork() {
        guard let containerURL else { return }
        let fileURL = containerURL.appendingPathComponent(Self.artworkFileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    public func reloadAllWidgets() {
        #if canImport(WidgetKit)
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "QuickShuffleWidget")
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }
}
