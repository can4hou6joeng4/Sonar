import Foundation
import SwiftData

public enum LibraryError: Error, LocalizedError, Equatable {
    case emptyPlaylistName
    case incompatiblePlaylistKind
    case personalPlaylistImmutable
    case systemPlaylistImmutable

    public var errorDescription: String? {
        switch self {
        case .emptyPlaylistName:
            return "歌单名称不能为空"
        case .incompatiblePlaylistKind:
            return "音乐只能收藏到音乐歌单"
        case .personalPlaylistImmutable:
            return "个人歌单不能删除"
        case .systemPlaylistImmutable:
            return "系统歌单不能重命名或删除"
        }
    }
}

public struct PersonalPlaylistCollectionResult {
    public let playlist: Playlist
    public let inserted: Bool
}

@MainActor
public final class LibraryStore {
    public static let recentPlaylistID = UUID(uuidString: "4CF93099-1702-4B9D-99DA-47B54D9B816B")!

    private let context: ModelContext
    private let recentLimit: Int

    public init(container: ModelContainer, recentLimit: Int = 100) {
        self.context = ModelContext(container)
        context.autosaveEnabled = false
        self.recentLimit = max(1, recentLimit)
    }

    public init(context: ModelContext, recentLimit: Int = 100) {
        self.context = context
        context.autosaveEnabled = false
        self.recentLimit = max(1, recentLimit)
    }

    public func playlists(includeSystem: Bool = true, includeArchived: Bool = false) throws -> [Playlist] {
        let descriptor = FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.name)])
        let playlists = try context.fetch(descriptor)
            .filter { includeArchived || !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        return includeSystem ? playlists : playlists.filter { !$0.isSystem }
    }

    @discardableResult
    public func ensurePersonalPlaylist() throws -> Playlist {
        let result = try normalizePersonalPlaylist()
        if result.didChange { try context.save() }
        WidgetShareStore.shared.updateFavoritesCount(result.playlist.items.count)
        return result.playlist
    }

    @discardableResult
    public func collect(_ track: Track) throws -> PersonalPlaylistCollectionResult {
        let normalization = try normalizePersonalPlaylist()
        let playlist = normalization.playlist
        guard !playlist.items.contains(where: { $0.track.musicId == track.musicID }) else {
            if normalization.didChange { try context.save() }
            WidgetShareStore.shared.updateFavoritesCount(playlist.items.count)
            return PersonalPlaylistCollectionResult(playlist: playlist, inserted: false)
        }
        _ = try insert(track, into: playlist)
        try context.save()
        WidgetShareStore.shared.updateFavoritesCount(playlist.items.count)
        return PersonalPlaylistCollectionResult(playlist: playlist, inserted: true)
    }

    private func normalizePersonalPlaylist() throws -> (playlist: Playlist, didChange: Bool) {
        // Archived playlists are retained migration sources, not ongoing mirrors.
        // Reimporting them would resurrect songs the user removed from the primary.
        let userPlaylists = try playlists(includeSystem: false)
        let primary: Playlist
        var didChange = false

        if let existing = userPlaylists.first(where: {
            $0.isPrimaryPersonal && $0.kind == .music
        }) {
            primary = existing
        } else if let existing = userPlaylists.first(where: {
            $0.kind == .music
        }) {
            primary = existing
        } else {
            let nextIndex = (try playlists(includeArchived: true).map(\.sortIndex).max() ?? -1) + 1
            primary = Playlist(
                name: "我喜欢的音乐",
                sortIndex: nextIndex,
                isPrimaryPersonal: true
            )
            context.insert(primary)
            didChange = true
        }

        if !primary.isPrimaryPersonal {
            primary.isPrimaryPersonal = true
            didChange = true
        }
        var existingIDs = Set(primary.orderedItems.map(\.track.musicId))
        var nextItemIndex = (primary.orderedItems.map(\.sortIndex).max() ?? -1) + 1
        for playlist in userPlaylists where playlist !== primary {
            for item in playlist.orderedItems where existingIDs.insert(item.track.musicId).inserted {
                let copy = PlaylistItem(sortIndex: nextItemIndex, playlist: primary, track: item.track)
                nextItemIndex += 1
                context.insert(copy)
                primary.items.append(copy)
                didChange = true
            }
            if playlist.isPrimaryPersonal {
                playlist.isPrimaryPersonal = false
                didChange = true
            }
            if !playlist.isArchived {
                playlist.isArchived = true
                didChange = true
            }
        }

        return (primary, didChange)
    }

    @discardableResult
    public func createPlaylist(
        named name: String,
        metadata: PlaylistMetadata = PlaylistMetadata()
    ) throws -> Playlist {
        let name = try validatedName(name)
        let nextIndex = (try playlists(includeArchived: true).map(\.sortIndex).max() ?? -1) + 1
        let playlist = Playlist(
            name: name,
            sortIndex: nextIndex,
            kindRaw: metadata.kind.rawValue,
            isShared: metadata.isShared,
            isPrivate: metadata.isPrivate
        )
        context.insert(playlist)
        try context.save()
        return playlist
    }

    public func rename(_ playlist: Playlist, to name: String) throws {
        guard !playlist.isSystem else { throw LibraryError.systemPlaylistImmutable }
        playlist.name = try validatedName(name)
        try context.save()
    }

    public func delete(_ playlist: Playlist) throws {
        guard !playlist.isSystem else { throw LibraryError.systemPlaylistImmutable }
        guard !playlist.isPrimaryPersonal else { throw LibraryError.personalPlaylistImmutable }
        context.delete(playlist)
        try normalizePlaylistOrder()
        try context.save()
    }

    public func movePlaylists(fromOffsets: IndexSet, toOffset: Int) throws {
        var userPlaylists = try playlists(includeSystem: false)
        let validOffsets = IndexSet(fromOffsets.filter { userPlaylists.indices.contains($0) })
        guard !validOffsets.isEmpty else { return }
        let moving = validOffsets.sorted().map { userPlaylists[$0] }
        for index in validOffsets.sorted(by: >) { userPlaylists.remove(at: index) }
        let removedBeforeDestination = validOffsets.filter { $0 < toOffset }.count
        let destination = min(max(toOffset - removedBeforeDestination, 0), userPlaylists.count)
        userPlaylists.insert(contentsOf: moving, at: destination)
        for (index, playlist) in userPlaylists.enumerated() { playlist.sortIndex = index }
        try context.save()
    }

    @discardableResult
    public func add(_ track: Track, to playlist: Playlist, at index: Int? = nil) throws -> PlaylistItem {
        let item = try insert(track, into: playlist, at: index)
        try context.save()
        if playlist.isPrimaryPersonal {
            WidgetShareStore.shared.updateFavoritesCount(playlist.items.count)
        }
        return item
    }

    private func insert(_ track: Track, into playlist: Playlist, at index: Int? = nil) throws -> PlaylistItem {
        guard playlist.kind == .music else { throw LibraryError.incompatiblePlaylistKind }
        let record = try upsert(track)
        let items = playlist.orderedItems
        let destination = min(max(index ?? items.count, 0), items.count)
        for item in items[destination...] { item.sortIndex += 1 }
        let item = PlaylistItem(sortIndex: destination, playlist: playlist, track: record)
        context.insert(item)
        playlist.items.append(item)
        return item
    }

    public func removeItem(at index: Int, from playlist: Playlist) throws {
        var items = playlist.orderedItems
        guard items.indices.contains(index) else { return }
        let removed = items.remove(at: index)
        context.delete(removed)
        for (sortIndex, item) in items.enumerated() { item.sortIndex = sortIndex }
        try context.save()
        if playlist.isPrimaryPersonal {
            WidgetShareStore.shared.updateFavoritesCount(items.count)
        }
    }

    public func moveItems(in playlist: Playlist, fromOffsets: IndexSet, toOffset: Int) throws {
        var items = playlist.orderedItems
        let validOffsets = IndexSet(fromOffsets.filter { items.indices.contains($0) })
        guard !validOffsets.isEmpty else { return }
        let moving = validOffsets.sorted().map { items[$0] }
        for index in validOffsets.sorted(by: >) { items.remove(at: index) }
        let removedBeforeDestination = validOffsets.filter { $0 < toOffset }.count
        let destination = min(max(toOffset - removedBeforeDestination, 0), items.count)
        items.insert(contentsOf: moving, at: destination)
        for (sortIndex, item) in items.enumerated() { item.sortIndex = sortIndex }
        try context.save()
    }

    @discardableResult
    public func recordRecent(_ track: Track) throws -> Playlist {
        let playlist = try recentPlaylist()
        let record = try upsert(track)
        let existing = playlist.items.first { $0.track.musicId == track.musicID }
        if let existing { context.delete(existing) }
        var items = playlist.orderedItems.filter { $0 !== existing }
        for item in items { item.sortIndex += 1 }
        let recent = PlaylistItem(sortIndex: 0, playlist: playlist, track: record)
        context.insert(recent)
        playlist.items.append(recent)
        items.insert(recent, at: 0)
        if items.count > recentLimit {
            for item in items[recentLimit...] { context.delete(item) }
        }
        try context.save()
        return playlist
    }

    public func recentTracks() throws -> [Track] {
        guard let playlist = try playlist(id: Self.recentPlaylistID) else { return [] }
        return playlist.orderedItems.compactMap { $0.track.track }
    }

    public func deleteTrack(_ track: Track) throws {
        let musicID = track.musicID
        var descriptor = FetchDescriptor<TrackRecord>(predicate: #Predicate { $0.musicId == musicID })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return }

        let matchingItems = try context.fetch(FetchDescriptor<PlaylistItem>()).filter {
            $0.track.musicId == musicID
        }
        let affectedPlaylists = matchingItems.compactMap(\.playlist).reduce(into: [UUID: Playlist]()) {
            $0[$1.id] = $1
        }

        for item in matchingItems { context.delete(item) }
        for playlist in affectedPlaylists.values {
            let remaining = playlist.orderedItems.filter { $0.track.musicId != musicID }
            for (index, item) in remaining.enumerated() { item.sortIndex = index }
        }
        context.delete(record)
        try context.save()
    }

    public func cacheAccentHex(_ accentHex: String?, for track: Track) throws {
        let record = try upsert(track)
        record.accentHex = accentHex
        try context.save()
    }

    @discardableResult
    public func updateTrack(_ track: Track) throws -> TrackRecord {
        let record = try upsert(track)
        try context.save()
        return record
    }

    private func recentPlaylist() throws -> Playlist {
        if let playlist = try playlist(id: Self.recentPlaylistID) { return playlist }
        let playlist = Playlist(id: Self.recentPlaylistID, name: "最近播放", sortIndex: -1, isSystem: true)
        context.insert(playlist)
        return playlist
    }

    private func playlist(id: UUID) throws -> Playlist? {
        var descriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func upsert(_ track: Track) throws -> TrackRecord {
        let musicID = track.musicID
        var descriptor = FetchDescriptor<TrackRecord>(predicate: #Predicate { $0.musicId == musicID })
        descriptor.fetchLimit = 1
        if let record = try context.fetch(descriptor).first {
            record.update(from: track)
            return record
        }
        let record = TrackRecord(track: track)
        context.insert(record)
        return record
    }

    private func normalizePlaylistOrder() throws {
        for (index, playlist) in try playlists(includeSystem: false).enumerated() {
            playlist.sortIndex = index
        }
    }

    private func validatedName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LibraryError.emptyPlaylistName }
        return name
    }
}
