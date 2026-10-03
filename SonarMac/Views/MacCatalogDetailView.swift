import SwiftUI

struct MacCatalogHeader: View {
    let title: String
    let subtitle: String
    let imageURL: String?
    let tracks: [Track]
    let model: MacAppModel
    var circle = false

    var body: some View {
        HStack(spacing: 24) {
            MacArtworkView(url: imageURL, size: 130, radius: circle ? 65 : 16)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 28, weight: .bold)).lineLimit(2)
                Text(subtitle).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 10) {
                    Button("播放", systemImage: "play.fill") { Task { await model.play(tracks) } }
                        .buttonStyle(.borderedProminent).disabled(tracks.isEmpty)
                    Button("收藏歌曲", systemImage: "heart") { tracks.forEach { model.collect($0) } }
                        .disabled(tracks.isEmpty)
                }.padding(.top, 4)
            }
            Spacer(minLength: 0)
        }.padding(26)
    }
}

struct MacArtistDetailView: View {
    let model: MacAppModel
    let open: (MacCatalogDestination) -> Void
    @State private var detail: ArtistDetailViewModel

    init(model: MacAppModel, artist: ArtistSummary, open: @escaping (MacCatalogDestination) -> Void) {
        self.model = model
        self.open = open
        _detail = State(initialValue: ArtistDetailViewModel(artist: artist, runtime: model.runtime))
    }

    private var tracks: [Track] { detail.selectedTab == .latest ? detail.latestTracks : detail.popularTracks }
    private var isLoading: Bool {
        switch detail.selectedTab {
        case .popular: detail.popularIsLoading
        case .latest: detail.latestIsLoading
        case .albums: detail.albumsIsLoading
        }
    }
    private var error: String? {
        switch detail.selectedTab {
        case .popular: detail.popularError
        case .latest: detail.latestError
        case .albums: detail.albumsError
        }
    }

    var body: some View {
        @Bindable var detail = detail
        VStack(alignment: .leading, spacing: 0) {
            MacCatalogHeader(title: detail.artist.name, subtitle: "歌手 · \(detail.artist.source.displayName)", imageURL: detail.artist.imageURL, tracks: tracks, model: model, circle: true)
            Picker("歌手内容", selection: $detail.selectedTab) {
                ForEach(ArtistDetailTab.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(width: 290).padding(.horizontal, 26).padding(.bottom, 20)
            if let error { MacInlineError(message: error, retry: reload).padding(.horizontal, 26).padding(.bottom, 12) }
            if isLoading {
                ProgressView("正在载入…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if detail.selectedTab == .albums {
                if detail.albums.isEmpty {
                    MacEmptyState(title: "暂无专辑", description: "此音源尚未返回歌手专辑。", symbol: "opticaldisc")
                } else {
                    ScrollView { MacAlbumGrid(albums: detail.albums, open: open).padding(26) }
                }
            } else {
                if detail.selectedTab == .latest, !detail.latestAlbums.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            ForEach(detail.latestAlbums, id: \.stableID) { album in
                                Button { open(.album(album)) } label: {
                                    HStack {
                                        MacArtworkView(url: album.imageURL, size: 45, radius: 7)
                                        VStack(alignment: .leading) {
                                            Text(album.name).lineLimit(1)
                                            Text(album.releaseDate ?? "专辑").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }.frame(width: 200, alignment: .leading)
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 26).padding(.bottom, 16)
                    }
                }
                MacTrackTable(model: model, tracks: tracks)
            }
        }.task(id: detail.selectedTab) { await detail.loadSelectedIfNeeded() }
    }

    private func reload() {
        Task {
            switch detail.selectedTab {
            case .popular: await detail.loadPopular()
            case .latest: await detail.loadLatest()
            case .albums: await detail.loadAlbums()
            }
        }
    }
}

private struct MacAlbumGrid: View {
    let albums: [AlbumSummary]
    let open: (MacCatalogDestination) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 20)], spacing: 24) {
            ForEach(albums, id: \.stableID) { album in
                Button { open(.album(album)) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        MacArtworkView(url: album.imageURL, size: 145, radius: 12)
                        Text(album.name).fontWeight(.medium).lineLimit(2)
                        Text(album.releaseDate ?? album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(width: 145, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
        }
    }
}

struct MacAlbumDetailView: View {
    let model: MacAppModel
    @State private var detail: AlbumDetailViewModel

    init(model: MacAppModel, album: AlbumSummary) {
        self.model = model
        _detail = State(initialValue: AlbumDetailViewModel(album: album, runtime: model.runtime))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacCatalogHeader(title: detail.album.name, subtitle: "\(detail.album.artist) · \(detail.album.releaseDate ?? "专辑")", imageURL: detail.album.imageURL, tracks: detail.tracks, model: model)
            if let error = detail.errorMessage {
                MacInlineError(message: error) { Task { await detail.load() } }.padding(.horizontal, 26).padding(.bottom, 16)
            }
            if detail.isLoading { ProgressView("正在载入专辑…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { MacTrackTable(model: model, tracks: detail.tracks) }
        }.task { await detail.load() }
    }
}

struct MacPlaylistDetailView: View {
    let model: MacAppModel
    let playlist: PlaylistSummary
    @State private var tracks: [Track] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var loadedPage = 0
    @State private var hasMore = false
    @State private var title: String?
    @State private var imageURL: String?
    @State private var total = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacCatalogHeader(title: title ?? playlist.name, subtitle: "\(playlist.author) · \(playlist.source.displayName) · \(total > 0 ? total : tracks.count) 首歌曲", imageURL: imageURL ?? playlist.img, tracks: tracks, model: model)
            if let description = playlist.desc, !description.isEmpty {
                Text(description).font(.callout).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                    .padding(.horizontal, 26).padding(.bottom, 16)
            }
            if let error { MacInlineError(message: error) { Task { await loadNextPage() } }.padding(.horizontal, 26).padding(.bottom, 12) }
            if isLoading, tracks.isEmpty {
                ProgressView("正在载入歌单…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { MacTrackTable(model: model, tracks: tracks) }
            if hasMore {
                HStack {
                    Text("已载入 \(tracks.count) / \(total) 首").foregroundStyle(.secondary)
                    Spacer()
                    Button(isLoading ? "正在载入…" : "载入更多") { Task { await loadNextPage() } }.disabled(isLoading)
                }.padding(16)
            }
        }.task { await loadNextPage() }
    }

    @MainActor private func loadNextPage() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let result = try await model.runtime.playlistDetail(source: playlist.source, id: playlist.id, page: loadedPage + 1)
            try Task.checkCancellation()
            var seen = Set(tracks.map(\.musicID))
            tracks.append(contentsOf: result.list.filter { seen.insert($0.musicID).inserted })
            loadedPage = result.page
            hasMore = result.hasMore
            total = result.total
            title = result.info.name
            imageURL = result.info.img
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}
