import SwiftData
import SwiftUI

struct ArtistDetailView: View {
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme
    @State private var model: ArtistDetailViewModel
    @State private var selectedTrack: Track?
    private let runtime: SourceRuntime

    init(artist: ArtistSummary, runtime: SourceRuntime) {
        self.runtime = runtime
        _model = State(initialValue: ArtistDetailViewModel(artist: artist, runtime: runtime))
    }

    var body: some View {
        VStack(spacing: 0) {
            artistHeader
            Picker("歌手内容", selection: $model.selectedTab) {
                ForEach(ArtistDetailTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityIdentifier("artist-detail-tabs")
            content
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .navigationTitle(model.artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.selectedTab) { await model.loadSelectedIfNeeded() }
        .onDisappear { model.invalidate() }
        .trackActionsDialog(track: $selectedTrack)
    }

    private var artistHeader: some View {
        HStack(spacing: 14) {
            RemotePlaylistArtwork(urlString: model.artist.imageURL)
                .frame(width: 76, height: 76)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 7) {
                Text(model.artist.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(scheme.onSurface)
                    .lineLimit(2)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(scheme.onSurfaceVariant)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("artist-detail-header-\(model.artist.stableID)")
    }

    @ViewBuilder
    private var content: some View {
        switch model.selectedTab {
        case .popular:
            trackContent(model.popularTracks, loading: model.popularIsLoading, error: model.popularError) {
                await model.loadPopular()
            }
        case .latest:
            latestContent
        case .albums:
            albumContent(model.albums, loading: model.albumsIsLoading, error: model.albumsError) {
                await model.loadAlbums()
            }
        }
    }

    private var latestContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.latestIsLoading, model.latestAlbums.isEmpty, model.latestTracks.isEmpty {
                    ProgressView("正在加载最新发行…").frame(maxWidth: .infinity, minHeight: 240)
                } else if let error = model.latestError, model.latestAlbums.isEmpty, model.latestTracks.isEmpty {
                    retryState("最新发行加载失败", error: error) { await model.loadLatest() }
                } else if model.latestAlbums.isEmpty {
                    ContentUnavailableView("暂无最新发行", systemImage: "sparkles")
                        .frame(minHeight: 240)
                } else {
                    Text("最新专辑")
                        .font(.headline).padding(.horizontal, 16).padding(.vertical, 10)
                    ForEach(model.latestAlbums, id: \.stableID) { albumRow($0) }
                    if !model.latestTracks.isEmpty {
                        Text("新作歌曲")
                            .font(.headline).padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 6)
                        trackRows(model.latestTracks)
                    }
                    if let error = model.latestError {
                        retryBanner(error) { await model.loadLatest() }
                    }
                }
            }
        }
        .accessibilityIdentifier("artist-latest-content")
    }

    private func trackContent(
        _ tracks: [Track],
        loading: Bool,
        error: String?,
        retry: @escaping () async -> Void
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if loading, tracks.isEmpty {
                    ProgressView("正在加载歌曲…").frame(maxWidth: .infinity, minHeight: 240)
                } else if let error, tracks.isEmpty {
                    retryState("歌曲加载失败", error: error, retry: retry)
                } else if tracks.isEmpty {
                    ContentUnavailableView("暂无歌曲", systemImage: "music.note")
                        .frame(minHeight: 240)
                } else {
                    trackRows(tracks)
                    if let error { retryBanner(error, retry: retry) }
                }
            }
        }
    }

    private func albumContent(
        _ albums: [AlbumSummary],
        loading: Bool,
        error: String?,
        retry: @escaping () async -> Void
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if loading, albums.isEmpty {
                    ProgressView("正在加载专辑…").frame(maxWidth: .infinity, minHeight: 240)
                } else if let error, albums.isEmpty {
                    retryState("专辑加载失败", error: error, retry: retry)
                } else if albums.isEmpty {
                    ContentUnavailableView("暂无专辑", systemImage: "square.stack")
                        .frame(minHeight: 240)
                } else {
                    ForEach(albums, id: \.stableID) { albumRow($0) }
                    if let error { retryBanner(error, retry: retry) }
                }
            }
        }
    }

    private func trackRows(_ tracks: [Track]) -> some View {
        ForEach(Array(tracks.enumerated()), id: \.element.musicID) { index, track in
            SongRow(
                track: track,
                leading: .index(index + 1),
                trailing: .more,
                showDivider: index < tracks.count - 1,
                isCurrent: playbackService.queue.current?.musicID == track.musicID,
                isPlaying: playbackService.state == .playing,
                onPlay: { Task { await playbackService.replaceQueue([track]) } },
                onAction: { selectedTrack = track }
            )
        }
    }

    private func albumRow(_ album: AlbumSummary) -> some View {
        NavigationLink {
            AlbumDetailView(album: album, runtime: runtime)
        } label: {
            HStack(spacing: 12) {
                RemotePlaylistArtwork(urlString: album.imageURL)
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 5) {
                    Text(album.name).font(.body).foregroundStyle(scheme.onSurface).lineLimit(1)
                    Text([album.releaseDate, album.trackCount.map { "\($0) 首" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(scheme.onSurfaceVariant).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(scheme.outline)
            }
            .padding(.horizontal, 16).frame(minHeight: 72).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("artist-album-\(album.stableID)")
    }

    private func retryState(_ title: String, error: String, retry: @escaping () async -> Void) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
        } description: {
            Text(error)
        } actions: {
            Button("重试") { Task { await retry() } }
        }
        .frame(minHeight: 240)
    }

    private func retryBanner(_ error: String, retry: @escaping () async -> Void) -> some View {
        HStack {
            Text(error).font(.caption).foregroundStyle(scheme.onSurfaceVariant).lineLimit(2)
            Spacer()
            Button("重试") { Task { await retry() } }
        }
        .padding(16)
    }

    private var metadata: String {
        var values: [String] = []
        if let count = model.artist.songCount, count > 0 { values.append("\(count) 首歌曲") }
        if let count = model.artist.albumCount, count > 0 { values.append("\(count) 张专辑") }
        return values.joined(separator: " · ")
    }
}

private struct TrackActionsDialogModifier: ViewModifier {
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.modelContext) private var modelContext
    @Binding var track: Track?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            track?.title ?? "歌曲操作",
            isPresented: Binding(get: { track != nil }, set: { if !$0 { track = nil } }),
            titleVisibility: .visible
        ) {
            Button("立即播放", systemImage: "play.fill") { perform { await playbackService.replaceQueue([$0]) } }
            Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") {
                perform { value in await playbackService.playNext(value); toastCenter.show("已设为下一首播放") }
            }
            Button("加入待播放", systemImage: "text.badge.plus") {
                perform { value in
                    let added = await playbackService.enqueue(value)
                    toastCenter.show(added ? "已加入待播放" : "歌曲已在待播放中")
                }
            }
            Button("收藏到歌单", systemImage: "music.note.list") {
                guard let value = track else { return }
                track = nil
                PersonalPlaylistCollectionFeedback.collect(
                    value,
                    context: modelContext,
                    toastCenter: toastCenter,
                    playbackService: playbackService
                )
            }
            Button("取消", role: .cancel) { track = nil }
        }
    }

    private func perform(_ action: @escaping (Track) async -> Void) {
        guard let value = track else { return }
        track = nil
        Task { await action(value) }
    }
}

extension View {
    func trackActionsDialog(track: Binding<Track?>) -> some View {
        modifier(TrackActionsDialogModifier(track: track))
    }
}
