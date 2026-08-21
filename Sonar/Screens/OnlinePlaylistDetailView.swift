import SwiftData
import SwiftUI

struct OnlinePlaylistDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter

    @State private var model: OnlinePlaylistDetailViewModel
    @State private var actionError: String?
    @State private var savedPlaylist: Playlist?
    @State private var isFavoriteActionRunning = false

    init(playlist: PlaylistSummary, runtime: SourceRuntime) {
        _model = State(initialValue: OnlinePlaylistDetailViewModel(playlist: playlist, runtime: runtime))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                hero
                metadata
                actions
                sectionHeader

                if model.isLoading, model.tracks.isEmpty {
                    skeletonRows
                } else if let error = model.errorMessage, model.tracks.isEmpty {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试") { Task { await model.loadInitial() } }
                    }
                    .frame(maxWidth: 900)
                } else if model.tracks.isEmpty {
                    ContentUnavailableView("这个歌单还没有曲目", systemImage: "music.note.list")
                        .frame(maxWidth: 900)
                } else {
                    ForEach(Array(model.visibleTracks.enumerated()), id: \.element.musicID) { index, track in
                        onlineTrackRow(track, queueIndex: index)
                            .onAppear {
                                guard track.musicID == model.visibleTracks.last?.musicID else { return }
                                Task { await model.loadMoreIfNeeded() }
                            }
                    }

                    continuationState
                }

                Color.clear.frame(height: 156)
            }
            .frame(maxWidth: .infinity)
        }
        .background(scheme.surface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .task { await model.loadInitial() }
        .alert("操作失败", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "未知错误")
        }
    }

    private var hero: some View {
        RemotePlaylistArtwork(urlString: model.info?.img ?? model.playlist.img)
            .frame(maxWidth: 900)
            .containerRelativeFrame(.horizontal)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .top) {
                HStack(spacing: 0) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.19), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回")
                    .accessibilityIdentifier("online-playlist-back")

                    Text("歌单详情")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.52), radius: 8)
                .padding()
            }
            .clipped()
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.info?.name ?? model.playlist.name)
                .font(.title.bold())
                .foregroundStyle(scheme.onSurface)
                .lineLimit(2)

            Text(metadataText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(scheme.onSurfaceVariant)
                .padding(.top, 8)

            if let description = displayDescription, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(scheme.onSurfaceVariant)
                    .lineLimit(2)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: 900, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var metadataText: String {
        let info = model.info
        let author = info?.author.isEmpty == false ? info?.author ?? "" : model.playlist.author
        let count = model.total > 0 ? model.total : model.playlist.total ?? model.tracks.count
        let playCount = info?.playCount.isEmpty == false ? info?.playCount ?? "" : model.playlist.playCount
        return "\(model.playlist.source.displayName) · \(author) · \(count) 首 · \(playCount) 次播放"
    }

    private var displayDescription: String? {
        let value = model.info?.desc ?? model.playlist.desc
        return value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var actions: some View {
        PlaylistDetailActions(
            isLoading: model.isLoading || model.isResolvingAllTracks,
            isFavoriteInProgress: isFavoriteActionRunning,
            isFavorite: savedPlaylist != nil,
            showFavorite: true,
            onPlayAll: playAll,
            onFavorite: { Task { await toggleFavorite() } }
        )
    }

    private var sectionHeader: some View {
        Text(model.sectionTitle)
            .font(.title3.weight(.bold))
            .foregroundStyle(scheme.onSurface)
            .frame(maxWidth: 900, minHeight: 24, alignment: .leading)
            .padding(.init(top: 16, leading: 16, bottom: 8, trailing: 16))
            .accessibilityIdentifier("online-playlist-track-count")
    }

    private var skeletonRows: some View {
        ForEach(0..<OnlinePlaylistDetailViewModel.trackPageSize, id: \.self) { _ in
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(scheme.surfaceContainerHighest)
                    .frame(width: 44, height: 44)

                GeometryReader { proxy in
                    VStack(alignment: .leading, spacing: 9) {
                        Capsule()
                            .fill(scheme.surfaceContainerHighest)
                            .frame(width: proxy.size.width * 0.58, height: 12)
                        Capsule()
                            .fill(scheme.surfaceContainerHigh)
                            .frame(width: proxy.size.width * 0.36, height: 9)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }

                Color.clear.frame(width: 44, height: 44)
            }
            .frame(maxWidth: 900)
            .frame(height: 62)
            .padding(.horizontal, 16)
            .accessibilityHidden(true)
        }
    }

    private func onlineTrackRow(_ track: Track, queueIndex: Int) -> some View {
        HStack(spacing: 9) {
            Button {
                Task { await playbackService.replaceQueue(model.tracks, startingAt: queueIndex) }
            } label: {
                HStack(spacing: 9) {
                    PlayerArtwork(track: track, size: 44, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 9) {
                        Text(track.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(scheme.onSurface)
                            .lineLimit(1)
                        Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(scheme.onSurfaceVariant)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { toastCenter.show("下载功能即将推出") } label: {
                Image(systemName: "arrow.down.circle")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(scheme.onSurfaceVariant)
            .accessibilityLabel("下载")
            .accessibilityIdentifier("online-playlist-download-\(track.musicID)")
        }
        .frame(maxWidth: 900)
        .frame(height: 62)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("online-playlist-track-\(track.musicID)")
    }

    @ViewBuilder
    private var continuationState: some View {
        if model.isLoadingMore {
            ProgressView()
                .frame(maxWidth: 900, minHeight: 62)
        } else if model.loadMoreError != nil {
            Button {
                Task { await model.loadMoreIfNeeded() }
            } label: {
                Label("重试加载更多", systemImage: "arrow.clockwise")
            }
            .frame(maxWidth: 900, minHeight: 62)
            .accessibilityIdentifier("online-playlist-retry-more")
        }
    }

    private func playAll() {
        Task {
            do {
                let tracks = try await model.allTracks()
                guard !tracks.isEmpty else { return }
                await playbackService.replaceQueue(tracks)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func toggleFavorite() async {
        guard !isFavoriteActionRunning else { return }
        isFavoriteActionRunning = true
        defer { isFavoriteActionRunning = false }
        do {
            let store = LibraryStore(context: modelContext)
            if let savedPlaylist {
                try store.delete(savedPlaylist)
                self.savedPlaylist = nil
                toastCenter.show("已取消收藏")
                return
            }
            let tracks = try await model.allTracks()
            let playlist = try store.createPlaylist(named: model.info?.name ?? model.playlist.name)
            for track in tracks {
                try store.add(track, to: playlist)
            }
            savedPlaylist = playlist
            toastCenter.show("已收藏到我的歌单")
        } catch {
            actionError = error.localizedDescription
        }
    }
}
