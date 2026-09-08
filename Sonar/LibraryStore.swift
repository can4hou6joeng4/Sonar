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

public struct TrackDetailCachePolicy: Sendable {
    public static let currentVersion = 1
    public static let production = TrackDetailCachePolicy()

    public let ttl: TimeInterval
    public let failureRetryDelay: TimeInterval

    public init(
        ttl: TimeInterval = 30 * 24 * 60 * 60,
        failureRetryDelay: TimeInterval = 6 * 60 * 60
    ) {
        self.ttl = max(0, ttl)
        self.failureRetryDelay = max(0, failureRetryDelay)
    }
}

public enum DetailRefreshDecision: Equatable, Sendable {
    case cached
    case retryDeferred(until: Date)
    case refresh
}

public enum TrackDetailRefreshError: Error, Equatable, Sendable {
    case identityMismatch(expected: String, received: String)
}

public enum TrackDetailRefreshOutcome: Sendable {
    case cached(Track)
    case refreshed(Track)
    case retryDeferred(Track, until: Date)
    case failedWithExistingData(Track)
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

    public func exportPersonalPlaylist() throws -> Data {
        let playlist = try ensurePersonalPlaylist()
        let tracks = try playlist.orderedItems.map { item in
            guard let track = item.track.track else { throw PlaylistBackupError.invalidTrack }
            return track
        }
        return try PlaylistBackup.encode(name: playlist.name, tracks: tracks)
    }

    @discardableResult
    public func importPersonalPlaylist(from data: Data) throws -> PlaylistImportResult {
        try importPersonalPlaylist(from: data, save: { try $0.save() })
    }

    // The save boundary is injectable so rollback is exercised without damaging a real store.
    func importPersonalPlaylist(
        from data: Data,
        save: (ModelContext) throws -> Void
    ) throws -> PlaylistImportResult {
        let backup = try PlaylistBackup.decode(data)
        guard !context.hasChanges else { throw PlaylistBackupError.pendingChanges }
        do {
            let normalization = try normalizePersonalPlaylist()
            let playlist = normalization.playlist
            if playlist.items.isEmpty { playlist.name = backup.name }
            var existingIDs = Set(playlist.orderedItems.map(\.track.musicId))
            var insertedCount = 0
            for track in backup.tracks where existingIDs.insert(track.musicID).inserted {
                _ = try insert(track, into: playlist)
                insertedCount += 1
            }
            if context.hasChanges { try save(context) }
            let result = PlaylistImportResult(
                insertedCount: insertedCount,
                skippedCount: backup.tracks.count - insertedCount,
                totalCount: playlist.items.count,
                playlistName: playlist.name
            )
            WidgetShareStore.shared.updateFavoritesCount(result.totalCount)
            return result
        } catch {
            context.rollback()
            throw PlaylistBackupError.saveFailed
        }
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

    public func detailRefreshDecision(
        for track: Track,
        now: Date = Date(),
        policy: TrackDetailCachePolicy = .production,
        force: Bool = false
    ) throws -> DetailRefreshDecision {
        if force { return .refresh }
        if track.highestKnownQuality != .standard { return .cached }

        let musicID = track.musicID
        var descriptor = FetchDescriptor<TrackRecord>(predicate: #Predicate { $0.musicId == musicID })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return .refresh }

        if record.detailRefreshVersion == TrackDetailCachePolicy.currentVersion,
           let refreshedAt = record.detailRefreshedAt,
           refreshedAt.addingTimeInterval(policy.ttl) > now {
            return .cached
        }
        if let retryAfter = record.detailRetryAfter, retryAfter > now {
            return .retryDeferred(until: retryAfter)
        }
        return .refresh
    }

    @discardableResult
    public func recordTrackDetailSuccess(
        _ refreshed: Track,
        requestedMusicID: String,
        at now: Date = Date(),
        version: Int = TrackDetailCachePolicy.currentVersion
    ) throws -> TrackRecord {
        guard refreshed.musicID == requestedMusicID else {
            throw TrackDetailRefreshError.identityMismatch(
                expected: requestedMusicID,
                received: refreshed.musicID
            )
        }
        let record = try upsert(refreshed)
        record.detailRefreshedAt = now
        record.detailRefreshVersion = version
        record.detailRetryAfter = nil
        try context.save()
        return record
    }

    public func recordTrackDetailFailure(
        for track: Track,
        retryAfter: Date
    ) throws {
        let musicID = track.musicID
        var descriptor = FetchDescriptor<TrackRecord>(predicate: #Predicate { $0.musicId == musicID })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return }
        record.detailRetryAfter = retryAfter
        try context.save()
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

@MainActor
public final class TrackDetailRefreshCoordinator {
    private struct Pending {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<NetworkResolution, Error>]
    }

    private enum NetworkResolution {
        case refreshed(Track)
        case failed
    }

    private let sourceRuntime: SourceRuntime
    private let policy: TrackDetailCachePolicy
    private var pending: [String: Pending] = [:]

    public init(
        sourceRuntime: SourceRuntime,
        policy: TrackDetailCachePolicy = .production
    ) {
        self.sourceRuntime = sourceRuntime
        self.policy = policy
    }

    public func refresh(
        _ track: Track,
        store: LibraryStore,
        force: Bool = false,
        now: Date = Date()
    ) async throws -> TrackDetailRefreshOutcome {
        switch try store.detailRefreshDecision(for: track, now: now, policy: policy, force: force) {
        case .cached:
            return .cached(track)
        case let .retryDeferred(until):
            return .retryDeferred(track, until: until)
        case .refresh:
            break
        }

        let resolution = try await networkResolution(for: track, store: store, now: now)
        try Task.checkCancellation()
        switch resolution {
        case let .refreshed(refreshed):
            return .refreshed(refreshed)
        case .failed:
            return .failedWithExistingData(track)
        }
    }

    func pendingConsumerCount(for musicID: String) -> Int {
        pending[musicID]?.waiters.count ?? 0
    }

    private func networkResolution(
        for track: Track,
        store: LibraryStore,
        now: Date
    ) async throws -> NetworkResolution {
        let key = track.musicID
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if pending[key] != nil {
                    pending[key]?.waiters[waiterID] = continuation
                    return
                }

                let requestID = UUID()
                let runtime = sourceRuntime
                let retryAfter = now.addingTimeInterval(policy.failureRetryDelay)
                let task = Task { @MainActor in
                    do {
                        let refreshed = try await runtime.trackDetail(track)
                        try Task.checkCancellation()
                        self.finish(
                            key: key,
                            requestID: requestID,
                            result: .success(refreshed),
                            store: store,
                            requestedTrack: track,
                            fetchedAt: now,
                            retryAfter: retryAfter
                        )
                    } catch {
                        self.finish(
                            key: key,
                            requestID: requestID,
                            result: .failure(error),
                            store: store,
                            requestedTrack: track,
                            fetchedAt: now,
                            retryAfter: retryAfter
                        )
                    }
                }
                pending[key] = Pending(
                    id: requestID,
                    task: task,
                    waiters: [waiterID: continuation]
                )
            }
        } onCancel: {
            Task { @MainActor in
                self.cancelWaiter(key: key, waiterID: waiterID)
            }
        }
    }

    private func cancelWaiter(key: String, waiterID: UUID) {
        guard let continuation = pending[key]?.waiters.removeValue(forKey: waiterID) else { return }
        continuation.resume(throwing: CancellationError())
        if pending[key]?.waiters.isEmpty == true {
            pending.removeValue(forKey: key)?.task.cancel()
        }
    }

    private func finish(
        key: String,
        requestID: UUID,
        result: Result<Track, Error>,
        store: LibraryStore,
        requestedTrack: Track,
        fetchedAt: Date,
        retryAfter: Date
    ) {
        guard let request = pending[key], request.id == requestID else { return }
        pending[key] = nil

        let resolution: Result<NetworkResolution, Error>
        switch result {
        case let .success(refreshed) where refreshed.musicID == key:
            // A successful network result remains useful even if the disposable
            // persistence write fails. The next launch will simply refresh again.
            _ = try? store.recordTrackDetailSuccess(
                refreshed,
                requestedMusicID: key,
                at: fetchedAt
            )
            resolution = .success(.refreshed(refreshed))
        case let .success(refreshed):
            try? store.recordTrackDetailFailure(for: requestedTrack, retryAfter: retryAfter)
            resolution = .failure(TrackDetailRefreshError.identityMismatch(
                expected: key,
                received: refreshed.musicID
            ))
        case let .failure(error) where Self.isCancellation(error):
            resolution = .failure(CancellationError())
        case .failure:
            try? store.recordTrackDetailFailure(for: requestedTrack, retryAfter: retryAfter)
            resolution = .success(.failed)
        }

        for waiter in request.waiters.values {
            waiter.resume(with: resolution)
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }
}
