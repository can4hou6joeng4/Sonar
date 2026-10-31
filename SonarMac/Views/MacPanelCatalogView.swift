import SwiftUI

/// 面板内的紧凑目录浏览：歌手、专辑与歌单都在状态栏面板里完成，不另开窗口。
struct MacPanelCatalogView: View {
    let model: MacAppModel
    let destination: MacCatalogDestination
    let push: (MacCatalogDestination) -> Void
    let back: () -> Void

    private var title: String {
        switch destination {
        case .artist(let artist): artist.name
        case .album(let album): album.name
        case .playlist(let playlist): playlist.name
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("返回搜索结果")
                .accessibilityLabel("返回搜索结果")
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            switch destination {
            case .artist(let artist):
                MacPanelArtistDetail(model: model, artist: artist, push: push)
            case .album(let album):
                MacPanelAlbumDetail(model: model, album: album)
            case .playlist(let playlist):
                MacPanelPlaylistDetail(model: model, playlist: playlist)
            }
        }
    }
}

/// 面板与目录页共用的紧凑歌曲行：已下架 / 不可用音源在这里显式标注并禁用播放。
struct MacCompactTrackRow: View {
    let track: Track
    let model: MacAppModel
    var isCurrent = false
    let action: () -> Void

    private var isRemoved: Bool { !track.isPlayable }
    private var isDisabledSource: Bool { !track.source.isEnabled }
    private var unplayable: Bool { isRemoved || isDisabledSource }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 9) {
                    MacArtworkView(track: track, service: model.artworkService, size: 32, radius: 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .lineLimit(1)
                            .fontWeight(isCurrent ? .semibold : .regular)
                        Text("\(track.artist) · \(track.source.displayName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(unplayable)
            .accessibilityLabel("播放 \(track.title)，\(track.artist)")
            .accessibilityHint(unplayable ? "该歌曲当前不可播放" : "")

            if isRemoved {
                MacStatusBadge(title: "已下架")
            } else if isDisabledSource {
                MacStatusBadge(title: "不可用")
            } else {
                Button { model.toggleFavorite(track) } label: {
                    Image(systemName: model.isFavorite(track) ? "heart.fill" : "heart")
                }
                .buttonStyle(.plain)
                .help(model.isFavorite(track) ? "取消收藏 \(track.title)" : "收藏 \(track.title)")
                .accessibilityLabel(model.isFavorite(track) ? "取消收藏 \(track.title)" : "收藏 \(track.title)")
                .disabled(model.library == nil)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 3)
    }
}

struct MacStatusBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel(title)
    }
}

/// 目录页共用的紧凑歌曲列表；点击即用当前列表组队列。
struct MacPanelTrackScroll: View {
    let tracks: [Track]
    let model: MacAppModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(tracks.enumerated()), id: \.element.musicID) { index, track in
                    MacCompactTrackRow(
                        track: track,
                        model: model,
                        isCurrent: model.playback.queue.current?.musicID == track.musicID
                    ) {
                        Task { await model.play(tracks, at: index) }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct MacPanelArtistDetail: View {
    let model: MacAppModel
    let push: (MacCatalogDestination) -> Void
    @State private var detail: ArtistDetailViewModel

    init(model: MacAppModel, artist: ArtistSummary, push: @escaping (MacCatalogDestination) -> Void) {
        self.model = model
        self.push = push
        _detail = State(initialValue: ArtistDetailViewModel(artist: artist, runtime: model.runtime))
    }

    private var tracks: [Track] {
        detail.selectedTab == .latest ? detail.latestTracks : detail.popularTracks
    }

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
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                MacArtworkView(url: detail.artist.imageURL, size: 42, radius: 21)
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.artist.name).fontWeight(.medium).lineLimit(1)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { Task { await model.play(tracks) } } label: {
                    Label("播放", systemImage: "play.fill")
                }
                .controlSize(.small)
                .disabled(tracks.isEmpty)
                .help("播放热门歌曲")
            }
            Picker("歌手内容", selection: $detail.selectedTab) {
                ForEach(ArtistDetailTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            if let error {
                MacInlineError(message: error, retry: reload)
            }
            content
        }
        .task(id: detail.selectedTab) { await detail.loadSelectedIfNeeded() }
    }

    private var subtitle: String {
        var parts = ["歌手", detail.artist.source.displayName]
        if let count = detail.artist.songCount, count > 0 { parts.append("\(count) 首") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var content: some View {
        if isLoading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 120)
        } else if detail.selectedTab == .albums {
            if detail.albums.isEmpty {
                empty("暂无专辑", description: "此音源尚未返回歌手专辑。")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 12) {
                        ForEach(detail.albums, id: \.stableID) { album in
                            Button { push(.album(album)) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    MacArtworkView(url: album.imageURL, size: 96, radius: 8)
                                    Text(album.name).font(.caption).lineLimit(2)
                                    Text(album.releaseDate ?? "专辑")
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } else if tracks.isEmpty {
            empty("暂无歌曲", description: "换一个歌手或稍后重试。")
        } else {
            MacPanelTrackScroll(tracks: tracks, model: model)
        }
    }

    private func empty(_ title: String, description: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(description).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
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

private struct MacPanelAlbumDetail: View {
    let model: MacAppModel
    @State private var detail: AlbumDetailViewModel

    init(model: MacAppModel, album: AlbumSummary) {
        self.model = model
        _detail = State(initialValue: AlbumDetailViewModel(album: album, runtime: model.runtime))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                MacArtworkView(url: detail.album.imageURL, size: 42, radius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.album.name).fontWeight(.medium).lineLimit(1)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { Task { await model.play(detail.tracks) } } label: {
                    Label("播放", systemImage: "play.fill")
                }
                .controlSize(.small)
                .disabled(detail.tracks.isEmpty)
            }
            if let error = detail.errorMessage {
                MacInlineError(message: error) { Task { await detail.load() } }
            }
            if detail.isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 120)
            } else if detail.tracks.isEmpty {
                Text("暂无曲目").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                MacPanelTrackScroll(tracks: detail.tracks, model: model)
            }
        }
        .task { await detail.load() }
    }

    private var subtitle: String {
        var parts = [detail.album.artist]
        if let date = detail.album.releaseDate, !date.isEmpty { parts.append(date) }
        if let count = detail.album.trackCount { parts.append("\(count) 首") }
        return parts.joined(separator: " · ")
    }
}

private struct MacPanelPlaylistDetail: View {
    let model: MacAppModel
    let playlist: PlaylistSummary
    @State private var tracks: [Track] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var loadedPage = 0
    @State private var hasMore = false
    @State private var info: PlaylistDetailInfo?
    @State private var total = 0

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                MacArtworkView(url: info?.img ?? playlist.img, size: 42, radius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info?.name ?? playlist.name).fontWeight(.medium).lineLimit(1)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { Task { await model.play(tracks) } } label: {
                    Label("播放", systemImage: "play.fill")
                }
                .controlSize(.small)
                .disabled(tracks.isEmpty)
            }
            if let error {
                MacInlineError(message: error) { Task { await loadNextPage() } }
            }
            if isLoading, tracks.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 120)
            } else if tracks.isEmpty {
                Text("歌单里还没有可播放的歌曲").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                MacPanelTrackScroll(tracks: tracks, model: model)
                if hasMore {
                    Button(isLoading ? "正在载入…" : "载入更多") { Task { await loadNextPage() } }
                        .controlSize(.small)
                        .disabled(isLoading)
                }
            }
        }
        .task { await loadNextPage() }
    }

    private var subtitle: String {
        var parts: [String] = []
        let author = info?.author ?? playlist.author
        if !author.isEmpty { parts.append(author) }
        parts.append("\((total > 0 ? total : tracks.count)) 首")
        return parts.joined(separator: " · ")
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
            info = result.info
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
