import SwiftUI

struct AlbumDetailView: View {
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme
    @State private var model: AlbumDetailViewModel
    @State private var selectedTrack: Track?

    init(album: AlbumSummary, runtime: SourceRuntime) {
        _model = State(initialValue: AlbumDetailViewModel(album: album, runtime: runtime))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                if model.isLoading, model.tracks.isEmpty {
                    ProgressView("正在加载专辑…").frame(maxWidth: .infinity, minHeight: 240)
                } else if let error = model.errorMessage, model.tracks.isEmpty {
                    ContentUnavailableView {
                        Label("专辑加载失败", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("重试") { Task { await model.load() } }
                    }
                    .frame(minHeight: 240)
                } else if model.tracks.isEmpty {
                    ContentUnavailableView("这张专辑暂无曲目", systemImage: "music.note.list")
                        .frame(minHeight: 240)
                } else {
                    ForEach(Array(model.tracks.enumerated()), id: \.element.musicID) { index, track in
                        SongRow(
                            track: track,
                            leading: .index(index + 1),
                            trailing: .more,
                            showAlbum: false,
                            showDivider: index < model.tracks.count - 1,
                            isCurrent: playbackService.queue.current?.musicID == track.musicID,
                            isPlaying: playbackService.state == .playing,
                            onPlay: { Task { await playbackService.replaceQueue([track]) } },
                            onAction: { selectedTrack = track }
                        )
                    }
                    if let error = model.errorMessage {
                        HStack(spacing: 12) {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(scheme.onSurfaceVariant)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Button("重试") { Task { await model.load() } }
                        }
                        .padding(16)
                        .accessibilityIdentifier("album-detail-retry-banner")
                    }
                }
            }
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .navigationTitle(model.album.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onDisappear { model.invalidate() }
        .trackActionsDialog(track: $selectedTrack)
        .accessibilityIdentifier("album-detail-\(model.album.stableID)")
    }

    private var header: some View {
        HStack(spacing: 16) {
            RemotePlaylistArtwork(urlString: model.album.imageURL)
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 7) {
                Text(model.album.name).font(.headline).foregroundStyle(scheme.onSurface).lineLimit(3)
                if !model.album.artist.isEmpty {
                    Text(model.album.artist).font(.subheadline).foregroundStyle(scheme.onSurfaceVariant).lineLimit(1)
                }
                Text([model.album.releaseDate, model.album.trackCount.map { "\($0) 首" }, model.album.source.displayName]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(scheme.onSurfaceVariant).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
