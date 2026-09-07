import Foundation
import Observation

enum DiscoveryContent {
    static let homeFreshTrackPageSize = 8
    static let homeFreshTrackMaximumBatches = 3
    static let homeFreshTrackLimit = homeFreshTrackPageSize * homeFreshTrackMaximumBatches

    static func merged(_ pages: [MusicSource: [PlaylistSummary]]) -> [PlaylistSummary] {
        let sourceLists = MusicSource.allCases.map { pages[$0] ?? [] }
        let maximumCount = sourceLists.map(\.count).max() ?? 0
        var seen = Set<String>()
        var result: [PlaylistSummary] = []

        for index in 0..<maximumCount {
            for list in sourceLists where list.indices.contains(index) {
                let playlist = list[index]
                if seen.insert(normalizedIdentity(for: playlist)).inserted {
                    result.append(playlist)
                }
            }
        }
        return result
    }

    static func deduplicatedTracks(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.musicID).inserted }
    }

    static func boundedHomeFreshTracks(_ tracks: [Track]) -> [Track] {
        Array(deduplicatedTracks(tracks).prefix(homeFreshTrackLimit))
    }

    static func playCountValue(_ text: String) -> Double {
        let compact = text.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let multiplier: Double
        if compact.contains("亿") {
            multiplier = 100_000_000
        } else if compact.contains("万") {
            multiplier = 10_000
        } else {
            multiplier = 1
        }
        let numeric = compact.filter { ($0 >= "0" && $0 <= "9") || $0 == "." }
        return (Double(numeric) ?? 0) * multiplier
    }

    private static func normalizedIdentity(for playlist: PlaylistSummary) -> String {
        let name = playlist.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { !$0.isWhitespace && !$0.isPunctuation }
        let author = playlist.author.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { !$0.isWhitespace && !$0.isPunctuation }
        let semanticKey = "\(name)|\(author)"
        return semanticKey == "|" ? playlist.key : semanticKey
    }
}

struct HomeFreshFeedScrollGate {
    static let minimumScrollDistance = 12.0
    static let nearEndDistance = 160.0

    private var initialContentTop: Double?
    private var lastTriggerOffset = 0.0
    private var lastTriggeredVisibleTrackCount: Int?
    private var lastTriggeredContentExtent: Double?

    mutating func shouldLoadMore(
        contentTop: Double,
        freshFeedEnd: Double,
        viewportHeight: Double,
        visibleTrackCount: Int
    ) -> Bool {
        guard contentTop.isFinite,
              freshFeedEnd.isFinite,
              viewportHeight > 0,
              visibleTrackCount > 0 else { return false }

        let contentExtent = freshFeedEnd - contentTop
        guard contentExtent > 0 else { return false }

        guard let initialContentTop else {
            self.initialContentTop = contentTop
            return false
        }

        let upwardOffset = max(0, initialContentTop - contentTop)
        if let lastTriggeredVisibleTrackCount, let lastTriggeredContentExtent {
            guard visibleTrackCount > lastTriggeredVisibleTrackCount,
                  contentExtent > lastTriggeredContentExtent else { return false }
        }
        guard upwardOffset >= lastTriggerOffset + Self.minimumScrollDistance,
              freshFeedEnd <= viewportHeight + Self.nearEndDistance else { return false }

        lastTriggerOffset = upwardOffset
        lastTriggeredVisibleTrackCount = visibleTrackCount
        lastTriggeredContentExtent = contentExtent
        return true
    }
}

struct HomeFreshFeedStateSnapshot: Equatable {
    let playlistKey: String?
    let trackIDs: [String]
    let bufferedTrackIDs: [String]
    let generation: Int
    let revealedBatches: Int
    let serverPage: Int
    let serverHasMore: Bool
    let isAtEnd: Bool
}

@MainActor
@Observable
final class HomeFreshFeedViewModel {
    private let runtime: SourceRuntime

    private(set) var tracks: [Track] = []
    private(set) var errorMessage: String?
    private(set) var loadMoreError: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isAtEnd = false

    private var playlist: PlaylistSummary?
    private var pendingPlaylist: PlaylistSummary?
    private var availableTracks: [Track] = []
    private var generation = 0
    private var revealedBatches = 0
    private var serverPage = 0
    private var serverHasMore = false

    init(runtime: SourceRuntime) {
        self.runtime = runtime
    }

    var hasStarted: Bool { playlist != nil || pendingPlaylist != nil }

    var stateSnapshot: HomeFreshFeedStateSnapshot {
        HomeFreshFeedStateSnapshot(
            playlistKey: playlist?.key,
            trackIDs: tracks.map(\.musicID),
            bufferedTrackIDs: availableTracks.map(\.musicID),
            generation: generation,
            revealedBatches: revealedBatches,
            serverPage: serverPage,
            serverHasMore: serverHasMore,
            isAtEnd: isAtEnd
        )
    }

    func loadInitialIfNeeded(from playlist: PlaylistSummary?) async {
        guard self.playlist == nil, pendingPlaylist == nil, let playlist else { return }
        await replaceStream(with: playlist)
    }

    func retryInitial() async {
        guard tracks.isEmpty,
              !isLoading,
              let playlist = pendingPlaylist ?? playlist else { return }
        await replaceStream(with: playlist)
    }

    func replaceStream(with playlist: PlaylistSummary) async {
        generation += 1
        let requestGeneration = generation
        pendingPlaylist = playlist
        errorMessage = nil
        loadMoreError = nil
        isLoading = true
        isLoadingMore = false

        do {
            let detail = try await runtime.playlistDetail(
                source: playlist.source,
                id: playlist.id,
                page: 1
            )
            guard requestGeneration == generation else { return }
            self.playlist = playlist
            pendingPlaylist = nil
            tracks = []
            availableTracks = []
            isAtEnd = false
            revealedBatches = 0
            serverPage = 0
            serverHasMore = false
            apply(detail)
            revealNextBatch()
            errorMessage = nil
            isLoading = false
        } catch is CancellationError {
            guard requestGeneration == generation else { return }
            isLoading = false
        } catch {
            guard requestGeneration == generation else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func loadMoreIfNeeded() async {
        guard let playlist,
              !tracks.isEmpty,
              !isLoading,
              !isLoadingMore,
              !isAtEnd else { return }

        if tracks.count < availableTracks.count {
            revealNextBatch()
            return
        }

        guard playlist.source == .wy, serverHasMore else {
            isAtEnd = true
            return
        }

        let requestGeneration = generation
        let nextPage = serverPage + 1
        isLoadingMore = true
        loadMoreError = nil
        do {
            let detail = try await runtime.playlistDetail(
                source: playlist.source,
                id: playlist.id,
                page: nextPage
            )
            guard requestGeneration == generation else { return }
            let previousCount = availableTracks.count
            apply(detail)
            if availableTracks.count > previousCount {
                revealNextBatch()
            } else {
                serverHasMore = false
                updateEndState()
            }
            isLoadingMore = false
        } catch is CancellationError {
            guard requestGeneration == generation else { return }
            isLoadingMore = false
        } catch {
            guard requestGeneration == generation else { return }
            loadMoreError = error.localizedDescription
            isLoadingMore = false
        }
    }

    private func apply(_ detail: PlaylistDetail) {
        let combined = availableTracks + detail.list
        availableTracks = DiscoveryContent.boundedHomeFreshTracks(combined)
        serverPage = max(serverPage, detail.page)
        serverHasMore = detail.hasMore && availableTracks.count < DiscoveryContent.homeFreshTrackLimit
        updateEndState()
    }

    private func revealNextBatch() {
        guard revealedBatches < DiscoveryContent.homeFreshTrackMaximumBatches,
              tracks.count < availableTracks.count else {
            updateEndState()
            return
        }
        revealedBatches += 1
        let visibleLimit = min(
            revealedBatches * DiscoveryContent.homeFreshTrackPageSize,
            DiscoveryContent.homeFreshTrackLimit
        )
        tracks = Array(availableTracks.prefix(visibleLimit))
        loadMoreError = nil
        updateEndState()
    }

    private func updateEndState() {
        if tracks.count >= DiscoveryContent.homeFreshTrackLimit
            || revealedBatches >= DiscoveryContent.homeFreshTrackMaximumBatches {
            isAtEnd = true
        } else if tracks.count < availableTracks.count {
            isAtEnd = false
        } else {
            isAtEnd = !serverHasMore
        }
    }
}

struct DiscoveryPageState: Sendable {
    var items: [PlaylistSummary] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var loadMoreError: String?
    var page = 0
    var hasMore = true
}

@MainActor
@Observable
final class DiscoveryViewModel {
    private let runtime: SourceRuntime
    let freshFeed: HomeFreshFeedViewModel
    private(set) var pages: [MusicSource: DiscoveryPageState] = [:]
    private(set) var selectedCategories: [MusicSource: PlaylistCategory] = [:]
    private var generations: [MusicSource: Int] = [:]
    private var currentFreshPlaylistIndex = 0

    init(runtime: SourceRuntime) {
        self.runtime = runtime
        freshFeed = HomeFreshFeedViewModel(runtime: runtime)
        for source in MusicSource.allCases {
            pages[source] = DiscoveryPageState()
            selectedCategories[source] = source.playlistCategories[0]
            generations[source] = 0
        }
    }

    func state(for source: MusicSource) -> DiscoveryPageState {
        pages[source] ?? DiscoveryPageState()
    }

    func selectedCategory(for source: MusicSource) -> PlaylistCategory {
        selectedCategories[source] ?? source.playlistCategories[0]
    }

    func loadHomeInitial() async {
        for source in MusicSource.allCases {
            await loadInitial(for: source)
        }
        await freshFeed.loadInitialIfNeeded(from: mergedPlaylists.first)
    }

    func refreshHomeCatalogs() async {
        for source in MusicSource.allCases {
            await refresh(source)
        }
    }

    func refreshHome() async {
        await refreshHomeCatalogs()
        await cycleFreshFeed()
    }

    func cycleFreshFeed() async {
        let playlists = mergedPlaylists
        guard !playlists.isEmpty else { return }
        currentFreshPlaylistIndex = (currentFreshPlaylistIndex + 1) % playlists.count
        await freshFeed.replaceStream(with: playlists[currentFreshPlaylistIndex])
    }

    func loadInitial(for source: MusicSource) async {
        let state = state(for: source)
        guard state.items.isEmpty, !state.isLoading else { return }
        let generation = generations[source, default: 0]
        await loadFirstPage(for: source, generation: generation, preserving: state)
    }

    func refresh(_ source: MusicSource) async {
        generations[source, default: 0] += 1
        let generation = generations[source, default: 0]
        await loadFirstPage(for: source, generation: generation, preserving: state(for: source))
    }

    func selectCategory(_ category: PlaylistCategory, for source: MusicSource) async {
        guard selectedCategory(for: source) != category else { return }
        selectedCategories[source] = category
        await refresh(source)
    }

    func loadMore(for source: MusicSource) async {
        var state = state(for: source)
        guard !state.items.isEmpty,
              state.hasMore,
              !state.isLoading,
              !state.isLoadingMore else { return }

        let generation = generations[source, default: 0]
        let nextPage = state.page + 1
        state.isLoadingMore = true
        state.loadMoreError = nil
        pages[source] = state

        do {
            let category = selectedCategory(for: source)
            let page = try await runtime.playlistCatalog(
                source: source,
                sortId: category.id,
                tagId: nil,
                page: nextPage
            )
            guard generations[source] == generation else { return }
            let existingKeys = Set(state.items.map(\.key))
            let additions = page.list.filter { !existingKeys.contains($0.key) }
            state.items.append(contentsOf: additions)
            state.page = page.page
            state.hasMore = !page.list.isEmpty && !additions.isEmpty
        } catch is CancellationError {
            guard generations[source] == generation else { return }
            state.isLoadingMore = false
            pages[source] = state
            return
        } catch {
            guard generations[source] == generation else { return }
            state.loadMoreError = error.localizedDescription
        }
        state.isLoadingMore = false
        pages[source] = state
    }

    private func loadFirstPage(
        for source: MusicSource,
        generation: Int,
        preserving existingState: DiscoveryPageState
    ) async {
        var state = existingState
        state.isLoading = true
        state.isLoadingMore = false
        state.errorMessage = nil
        state.loadMoreError = nil
        pages[source] = state

        do {
            let category = selectedCategory(for: source)
            let page = try await runtime.playlistCatalog(
                source: source,
                sortId: category.id,
                tagId: nil,
                page: 1
            )
            guard generations[source] == generation else { return }
            state.items = page.list
            state.page = page.page
            state.hasMore = !page.list.isEmpty
        } catch is CancellationError {
            guard generations[source] == generation else { return }
            state.isLoading = false
            pages[source] = state
            return
        } catch {
            guard generations[source] == generation else { return }
            state.errorMessage = error.localizedDescription
        }
        state.isLoading = false
        pages[source] = state
    }

    var mergedPlaylists: [PlaylistSummary] {
        DiscoveryContent.merged(Dictionary(uniqueKeysWithValues: MusicSource.allCases.map {
            ($0, state(for: $0).items)
        }))
    }
}
