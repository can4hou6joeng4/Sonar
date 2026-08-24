import SwiftData
import SwiftUI

struct FavoritePlaylistRegistry {
    private static let storageKey = "favoriteRemotePlaylists"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func playlistID(for remoteKey: String) -> UUID? {
        mapping()[remoteKey].flatMap(UUID.init(uuidString:))
    }

    func register(remoteKey: String, playlistID: UUID) {
        var values = mapping()
        values[remoteKey] = playlistID.uuidString
        save(values)
    }

    func unregister(remoteKey: String) {
        var values = mapping()
        values[remoteKey] = nil
        save(values)
    }

    func unregister(playlistID: UUID) {
        let id = playlistID.uuidString
        save(mapping().filter { $0.value != id })
    }

    @discardableResult
    func prune(validPlaylistIDs: Set<UUID>) -> Set<UUID> {
        let validStrings = Set(validPlaylistIDs.map(\.uuidString))
        let cleaned = mapping().filter { validStrings.contains($0.value) }
        save(cleaned)
        return Set(cleaned.values.compactMap(UUID.init(uuidString:)))
    }

    private func mapping() -> [String: String] {
        defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
    }

    private func save(_ mapping: [String: String]) {
        defaults.set(mapping, forKey: Self.storageKey)
    }
}

struct OnlinePlaylistDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.shellSafeAreaInsets) private var safeAreaInsets
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Query(filter: #Predicate<Playlist> { !$0.isSystem }, sort: \Playlist.sortIndex)
    private var localPlaylists: [Playlist]

    @State private var model: OnlinePlaylistDetailViewModel
    @State private var selectedTrackForPlaylist: Track?
    @State private var savedPlaylist: Playlist?
    @State private var isFavoriteActionRunning = false
    @State private var actionError: String?
    @State private var navIsSolid = false

    init(playlist: PlaylistSummary, runtime: SourceRuntime) {
        _model = State(initialValue: OnlinePlaylistDetailViewModel(playlist: playlist, runtime: runtime))
    }

    private var title: String { model.info?.name ?? model.playlist.name }
    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    trackList
                        .offset(y: -12)
                }
                .background {
                    NCMScrollThresholdObserver(threshold: 120) { navIsSolid = $0 }
                }
            }
            .scrollIndicators(.hidden)

            navigationBar
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .ncmEdgeSwipeBack()
        .task {
            restoreFavorite()
            await model.loadInitial()
        }
        .sheet(item: $selectedTrackForPlaylist) { track in
            AddToPlaylistSheet(track: track)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
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
        GeometryReader { proxy in
            ZStack {
                RemotePlaylistArtwork(urlString: model.info?.img ?? model.playlist.img)
                    .frame(width: proxy.size.width + 120, height: proxy.size.height + 120)
                    .blur(radius: 40)
                    .saturation(1.5)
                    .scaleEffect(1.25)
                LinearGradient(
                    colors: [.black.opacity(0.46), .black.opacity(0.32), .black.opacity(0.50)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(alignment: .center, spacing: 14) {
                    RemotePlaylistArtwork(urlString: model.info?.img ?? model.playlist.img)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 9, y: 6)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(metadataText)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(1)
                        if let description = displayDescription, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                        Button {
                            Task { await toggleFavorite() }
                        } label: {
                            HStack(spacing: 5) {
                                if isFavoriteActionRunning { ProgressView().tint(.white).controlSize(.mini) }
                                else { Image(systemName: savedPlaylist == nil ? "heart" : "heart.fill") }
                                Text(savedPlaylist == nil ? "收藏" : "已收藏")
                            }
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isFavoriteActionRunning || model.isLoading)
                        .accessibilityIdentifier("playlist-favorite")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
                .padding(.top, safeAreaInsets.top + 60)
                .padding(.bottom, 24)
            }
            .clipped()
        }
        .frame(height: safeAreaInsets.top + 244)
    }

    private var navigationBar: some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")
            .accessibilityIdentifier("online-playlist-back")

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .opacity(navIsSolid ? 1 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(navIsSolid ? scheme.onSurface : Color.white)
        .padding(.horizontal, 4)
        .padding(.top, safeAreaInsets.top)
        .background(navIsSolid ? scheme.appSurface : Color.clear)
        .animation(.easeOut(duration: 0.18), value: navIsSolid)
    }

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            playAllRow
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
                .frame(minHeight: 260)
            } else if model.tracks.isEmpty {
                ContentUnavailableView("这个歌单还没有曲目", systemImage: "music.note.list")
                    .frame(minHeight: 260)
            } else {
                ForEach(Array(model.visibleTracks.enumerated()), id: \.element.musicID) { index, track in
                    SongRow(
                        track: track,
                        leading: .index(index + 1),
                        trailing: .more,
                        showAlbum: false,
                        showDivider: index < model.visibleTracks.count - 1 || model.hasMoreContent,
                        isCurrent: playbackService.queue.current?.musicID == track.musicID,
                        isPlaying: playbackService.state == .playing,
                        onPlay: { Task { await playbackService.replaceQueue(model.tracks, startingAt: index) } },
                        onAction: { selectedTrackForPlaylist = track }
                    )
                    .onAppear {
                        guard track.musicID == model.visibleTracks.last?.musicID else { return }
                        Task { await model.loadMoreIfNeeded() }
                    }
                }
                continuationState
            }
            Color.clear.frame(height: 146)
        }
        .background(scheme.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var playAllRow: some View {
        Button(action: playAll) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(scheme.primary)
                Text("播放全部")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(scheme.onSurface)
                Text("(\(max(model.total, model.tracks.count)))")
                    .font(.system(size: 12))
                    .foregroundStyle(scheme.onSurfaceVariant)
                Spacer(minLength: 0)
                if model.isResolvingAllTracks { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isLoading || model.isResolvingAllTracks || model.tracks.isEmpty)
        .accessibilityIdentifier("playlist-play-all")
    }

    private var skeletonRows: some View {
        ForEach(0..<6, id: \.self) { index in
            HStack(spacing: 10) {
                Text("\(index + 1)").frame(width: 26)
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(scheme.surfaceContainerHigh).frame(width: 150, height: 11)
                    Capsule().fill(scheme.surfaceContainer).frame(width: 105, height: 9)
                }
                Spacer()
            }
            .foregroundStyle(scheme.outline)
            .padding(.horizontal, 16)
            .frame(height: 60)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var continuationState: some View {
        if model.isLoadingMore {
            ProgressView().frame(maxWidth: .infinity, minHeight: 54)
        } else if model.loadMoreError != nil {
            Button("重试加载更多") { Task { await model.loadMoreIfNeeded() } }
                .frame(maxWidth: .infinity, minHeight: 54)
                .accessibilityIdentifier("online-playlist-retry-more")
        }
    }

    private var metadataText: String {
        let info = model.info
        let author = info?.author.isEmpty == false ? info?.author ?? "" : model.playlist.author
        let playCount = info?.playCount.isEmpty == false ? info?.playCount ?? "" : model.playlist.playCount
        return [author, playCount.isEmpty ? nil : "\(playCount) 次播放"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var displayDescription: String? {
        (model.info?.desc ?? model.playlist.desc)?.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func restoreFavorite() {
        let registry = FavoritePlaylistRegistry()
        _ = registry.prune(validPlaylistIDs: Set(localPlaylists.map(\.id)))
        guard let playlistID = registry.playlistID(for: model.playlist.key) else {
            savedPlaylist = nil
            return
        }
        savedPlaylist = localPlaylists.first { $0.id == playlistID }
    }

    private func toggleFavorite() async {
        guard !isFavoriteActionRunning else { return }
        isFavoriteActionRunning = true
        defer { isFavoriteActionRunning = false }
        let registry = FavoritePlaylistRegistry()
        do {
            let store = LibraryStore(context: modelContext)
            if let savedPlaylist {
                try store.delete(savedPlaylist)
                registry.unregister(remoteKey: model.playlist.key)
                self.savedPlaylist = nil
                toastCenter.show("已取消收藏")
                return
            }
            let tracks = try await model.allTracks()
            let playlist = try store.createPlaylist(named: title)
            for track in tracks { try store.add(track, to: playlist) }
            registry.register(remoteKey: model.playlist.key, playlistID: playlist.id)
            savedPlaylist = playlist
            toastCenter.show("已收藏到我的歌单")
        } catch {
            actionError = error.localizedDescription
        }
    }
}
