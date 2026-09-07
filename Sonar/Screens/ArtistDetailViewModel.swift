import Foundation
import Observation

enum ArtistDetailTab: String, CaseIterable, Identifiable {
    case popular = "热门"
    case latest = "最新"
    case albums = "专辑"

    var id: String { rawValue }
}

@MainActor
@Observable
final class ArtistDetailViewModel {
    let artist: ArtistSummary
    var selectedTab: ArtistDetailTab = .popular
    var popularTracks: [Track] = []
    var latestAlbums: [AlbumSummary] = []
    var latestTracks: [Track] = []
    var albums: [AlbumSummary] = []
    var popularIsLoading = false
    var latestIsLoading = false
    var albumsIsLoading = false
    var popularError: String?
    var latestError: String?
    var albumsError: String?

    private let runtime: SourceRuntime
    private var popularGeneration = 0
    private var latestGeneration = 0
    private var albumsGeneration = 0

    init(artist: ArtistSummary, runtime: SourceRuntime) {
        self.artist = artist
        self.runtime = runtime
    }

    func loadSelectedIfNeeded() async {
        switch selectedTab {
        case .popular where popularTracks.isEmpty && popularError == nil:
            await loadPopular()
        case .latest where latestAlbums.isEmpty && latestTracks.isEmpty && latestError == nil:
            await loadLatest()
        case .albums where albums.isEmpty && albumsError == nil:
            await loadAlbums()
        default:
            break
        }
    }

    func loadPopular() async {
        popularGeneration += 1
        let generation = popularGeneration
        popularIsLoading = true
        popularError = nil
        do {
            let tracks = try await runtime.artistPopularTracks(artist)
            try Task.checkCancellation()
            guard generation == popularGeneration else { return }
            popularTracks = deduplicated(tracks)
            popularIsLoading = false
        } catch is CancellationError {
            guard generation == popularGeneration else { return }
            popularIsLoading = false
        } catch {
            guard generation == popularGeneration else { return }
            popularIsLoading = false
            popularError = error.localizedDescription
        }
    }

    func loadLatest() async {
        latestGeneration += 1
        let generation = latestGeneration
        latestIsLoading = true
        latestError = nil
        do {
            let page = try await runtime.artistAlbums(artist, page: 1)
            try Task.checkCancellation()
            guard generation == latestGeneration else { return }
            let newest = Array(sortedNewestFirst(page.list).prefix(6))
            var tracks: [Track] = []
            var trackFailure: Error?
            for album in newest.prefix(3) {
                do {
                    tracks.append(contentsOf: try await runtime.albumTracks(album).tracks)
                    try Task.checkCancellation()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    trackFailure = error
                }
                guard generation == latestGeneration else { return }
            }
            if newest.isEmpty == false, tracks.isEmpty, let trackFailure { throw trackFailure }
            latestAlbums = newest
            latestTracks = deduplicated(tracks)
            if trackFailure != nil, !tracks.isEmpty {
                latestError = "部分最新专辑曲目暂不可用，请重试"
            }
            latestIsLoading = false
        } catch is CancellationError {
            guard generation == latestGeneration else { return }
            latestIsLoading = false
        } catch {
            guard generation == latestGeneration else { return }
            latestIsLoading = false
            latestError = error.localizedDescription
        }
    }

    func loadAlbums() async {
        albumsGeneration += 1
        let generation = albumsGeneration
        albumsIsLoading = true
        albumsError = nil
        do {
            let page = try await runtime.artistAlbums(artist, page: 1)
            try Task.checkCancellation()
            guard generation == albumsGeneration else { return }
            albums = deduplicated(sortedNewestFirst(page.list))
            albumsIsLoading = false
        } catch is CancellationError {
            guard generation == albumsGeneration else { return }
            albumsIsLoading = false
        } catch {
            guard generation == albumsGeneration else { return }
            albumsIsLoading = false
            albumsError = error.localizedDescription
        }
    }

    func invalidate() {
        popularGeneration += 1
        latestGeneration += 1
        albumsGeneration += 1
        popularIsLoading = false
        latestIsLoading = false
        albumsIsLoading = false
    }

    private func deduplicated(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.musicID).inserted }
    }

    private func deduplicated(_ albums: [AlbumSummary]) -> [AlbumSummary] {
        var seen = Set<String>()
        return albums.filter { seen.insert($0.stableID).inserted }
    }

    private func sortedNewestFirst(_ albums: [AlbumSummary]) -> [AlbumSummary] {
        albums.enumerated().sorted { lhs, rhs in
            let leftDate = lhs.element.releaseDate ?? ""
            let rightDate = rhs.element.releaseDate ?? ""
            if leftDate != rightDate { return leftDate > rightDate }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

@MainActor
@Observable
final class AlbumDetailViewModel {
    let requestedAlbum: AlbumSummary
    var album: AlbumSummary
    var tracks: [Track] = []
    var isLoading = false
    var errorMessage: String?

    private let runtime: SourceRuntime
    private var generation = 0

    init(album: AlbumSummary, runtime: SourceRuntime) {
        requestedAlbum = album
        self.album = album
        self.runtime = runtime
    }

    func load() async {
        generation += 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = nil
        do {
            let detail = try await runtime.albumTracks(requestedAlbum)
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            album = detail.album
            var seen = Set<String>()
            tracks = detail.tracks.filter { seen.insert($0.musicID).inserted }
            isLoading = false
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            isLoading = false
        } catch {
            guard generation == requestGeneration else { return }
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func invalidate() {
        generation += 1
        isLoading = false
    }
}
