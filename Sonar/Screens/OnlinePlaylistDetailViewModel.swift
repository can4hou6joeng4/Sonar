import Foundation
import Observation

@MainActor
@Observable
final class OnlinePlaylistDetailViewModel {
    static let trackPageSize = 40

    let playlist: PlaylistSummary

    private let runtime: SourceRuntime
    private(set) var info: PlaylistDetailInfo?
    private(set) var tracks: [Track] = []
    private(set) var total = 0
    private(set) var visibleCount = 0
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isResolvingAllTracks = false
    private(set) var errorMessage: String?
    private(set) var loadMoreError: String?
    private var page = 0
    private var limit = 0
    private var canLoadAnotherPage = true

    init(playlist: PlaylistSummary, runtime: SourceRuntime) {
        self.playlist = playlist
        self.runtime = runtime
    }

    var visibleTracks: [Track] {
        Array(tracks.prefix(visibleCount))
    }

    var sectionTitle: String {
        let loaded = tracks.count
        return total > loaded ? "歌曲  \(loaded)/\(total)" : "歌曲  \(loaded)"
    }

    var hasMoreContent: Bool {
        visibleCount < tracks.count || canLoadAnotherPage
    }

    func loadInitial() async {
        guard tracks.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let detail = try await runtime.playlistDetail(source: playlist.source, id: playlist.id, page: 1)
            applyInitial(detail)
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMoreIfNeeded() async {
        guard !isLoading, !isLoadingMore, !isResolvingAllTracks else { return }

        if visibleCount < tracks.count {
            visibleCount = min(visibleCount + Self.trackPageSize, tracks.count)
            return
        }

        guard canLoadAnotherPage else { return }
        isLoadingMore = true
        loadMoreError = nil
        do {
            let additions = try await fetchNextPage()
            visibleCount = min(visibleCount + Self.trackPageSize, tracks.count)
            if additions == 0 { canLoadAnotherPage = false }
        } catch is CancellationError {
            isLoadingMore = false
            return
        } catch {
            loadMoreError = error.localizedDescription
        }
        isLoadingMore = false
    }

    func allTracks() async throws -> [Track] {
        if tracks.isEmpty { await loadInitial() }
        if let errorMessage, tracks.isEmpty {
            throw SourceError.source(message: errorMessage)
        }
        guard !isResolvingAllTracks else { return tracks }

        isResolvingAllTracks = true
        defer { isResolvingAllTracks = false }
        while canLoadAnotherPage {
            let additions = try await fetchNextPage()
            if additions == 0 { canLoadAnotherPage = false }
        }
        visibleCount = min(max(visibleCount, Self.trackPageSize), tracks.count)
        return tracks
    }

    private func applyInitial(_ detail: PlaylistDetail) {
        info = detail.info
        tracks = deduplicated(detail.list)
        total = max(detail.total, tracks.count)
        page = detail.page
        limit = detail.limit
        visibleCount = min(Self.trackPageSize, tracks.count)
        canLoadAnotherPage = detail.hasMore
    }

    @discardableResult
    private func fetchNextPage() async throws -> Int {
        guard canLoadAnotherPage, playlist.source == .wy else {
            canLoadAnotherPage = false
            return 0
        }

        let detail = try await runtime.playlistDetail(source: playlist.source, id: playlist.id, page: page + 1)
        let existingIDs = Set(tracks.map(\.musicID))
        let additions = detail.list.filter { !existingIDs.contains($0.musicID) }
        tracks.append(contentsOf: additions)
        info = detail.info
        total = max(detail.total, tracks.count)
        page = detail.page
        limit = detail.limit
        canLoadAnotherPage = detail.hasMore && !additions.isEmpty
        return additions.count
    }

    private func deduplicated(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.musicID).inserted }
    }
}
