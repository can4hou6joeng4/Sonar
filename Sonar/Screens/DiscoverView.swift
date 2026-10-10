import SwiftData
import SwiftUI

struct DiscoverView: View {
    let isActive: Bool
    let onOpenSearch: () -> Void
    let onOpenSettings: () -> Void
    let onSettingsDragChanged: (DragGesture.Value) -> Void
    let onSettingsDragEnded: (DragGesture.Value) -> Void

    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.trackDetailRefreshCoordinator) private var trackDetailRefreshCoordinator
    @Query(sort: \Playlist.sortIndex) private var libraryPlaylists: [Playlist]
    @State private var actionError: String?
    @State private var selectedTrackForActions: Track?

    init(
        isActive: Bool,
        onOpenSearch: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onSettingsDragChanged: @escaping (DragGesture.Value) -> Void = { _ in },
        onSettingsDragEnded: @escaping (DragGesture.Value) -> Void = { _ in }
    ) {
        self.isActive = isActive
        self.onOpenSearch = onOpenSearch
        self.onOpenSettings = onOpenSettings
        self.onSettingsDragChanged = onSettingsDragChanged
        self.onSettingsDragEnded = onSettingsDragEnded
    }

    private var personalPlaylist: Playlist? {
        libraryPlaylists.first {
            $0.isPrimaryPersonal && !$0.isArchived && !$0.isSystem && $0.kind == .music
        }
    }

    var body: some View {
        let playlist = personalPlaylist
        let tracks = playlist?.orderedItems.compactMap { $0.track.track } ?? []

        VStack(spacing: 0) {
            header
            homeContent(playlist: playlist, tracks: tracks)
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .rootSettingsDrawerGesture(
            isEnabled: isActive,
            onOpen: onOpenSettings,
            onChanged: onSettingsDragChanged,
            onEnded: onSettingsDragEnded
        )
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            selectedTrackForActions?.title ?? "歌曲操作",
            isPresented: Binding(
                get: { selectedTrackForActions != nil },
                set: { if !$0 { selectedTrackForActions = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let track = selectedTrackForActions {
                Button("立即播放", systemImage: "play.fill") {
                    selectedTrackForActions = nil
                    Task { await playbackService.replaceQueue([track]) }
                }
                Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    selectedTrackForActions = nil
                    Task {
                        await playbackService.playNext(track)
                        toastCenter.show("已设为下一首播放")
                    }
                }
                Button("加入待播放", systemImage: "text.badge.plus") {
                    selectedTrackForActions = nil
                    Task {
                        let added = await playbackService.enqueue(track)
                        toastCenter.show(added ? "已加入待播放" : "歌曲已在待播放中")
                    }
                }
                Button("移出歌单", systemImage: "trash", role: .destructive) {
                    selectedTrackForActions = nil
                    removeTrack(track)
                }
                Button("取消", role: .cancel) { selectedTrackForActions = nil }
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "未知错误")
        }
        .task {
            do {
                _ = try LibraryStore(context: modelContext).ensurePersonalPlaylist()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Sonar")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(scheme.onSurface)
            Spacer()
            Button(action: onOpenSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(scheme.onSurface)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.circleIcon(diameter: 38))
            .accessibilityLabel("搜索")
            .accessibilityIdentifier("home-search-button")
        }
        .frame(minHeight: NCMDesignTokens.Layout.navigationHeight)
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .padding(.top, 6)
    }

    private func homeContent(playlist: Playlist?, tracks: [Track]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                playlistHeader(playlist: playlist, tracks: tracks)

                if !tracks.isEmpty {
                    ForEach(Array(tracks.enumerated()), id: \.element.musicID) { index, track in
                        SongRow(
                            track: track,
                            leading: .cover,
                            trailing: .more,
                            showDivider: index < tracks.count - 1,
                            isCurrent: playbackService.queue.current?.musicID == track.musicID,
                            isPlaying: playbackService.state == .playing,
                            onPlay: { Task { await playbackService.replaceQueue(tracks, startingAt: index, activePlaylistID: playlist?.id) } },
                            onAction: { selectedTrackForActions = track }
                        )
                        .contextMenu {
                            Button {
                                Task { await playbackService.replaceQueue(tracks, startingAt: index, activePlaylistID: playlist?.id) }
                            } label: {
                                Label("立即播放", systemImage: "play.fill")
                            }
                            Button {
                                Task {
                                    await playbackService.playNext(track)
                                    toastCenter.show("已设为下一首播放")
                                }
                            } label: {
                                Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward")
                            }
                            Button {
                                Task {
                                    let added = await playbackService.enqueue(track)
                                    toastCenter.show(added ? "已加入待播放" : "歌曲已在待播放中")
                                }
                            } label: {
                                Label("加入待播放", systemImage: "text.badge.plus")
                            }
                            Divider()
                            Button(role: .destructive) {
                                removeTrack(track, from: playlist)
                            } label: {
                                Label("移出歌单", systemImage: "trash")
                            }
                        }
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(scheme.onSurfaceVariant.opacity(0.4))
                            .padding(.top, 48)
                            .accessibilityHidden(true)

                        Text("还没有收藏的音乐")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(scheme.onSurface)

                        Text("点击右上角搜索，发现并收藏你喜爱的歌曲")
                            .font(.system(size: 13))
                            .foregroundStyle(scheme.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }

                Color.clear.frame(height: 32)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await refreshTrackDetails(tracks, limit: 50, force: true)
        }
    }

    private func playlistHeader(playlist: Playlist?, tracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(tracks.count) 首歌曲")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(scheme.onSurfaceVariant)
                .accessibilityIdentifier("home-playlist-count")

            HStack(spacing: 10) {
                playlistActionButton(
                    title: "播放全部",
                    systemImage: "play.fill",
                    foreground: scheme.onPrimary,
                    background: scheme.primary,
                    identifier: "home-play-all-button",
                    isDisabled: tracks.isEmpty,
                    action: { playAll(playlist: playlist, tracks: tracks) }
                )
                playlistActionButton(
                    title: "随机播放",
                    systemImage: "shuffle",
                    foreground: scheme.onSurface,
                    background: scheme.surfaceContainerHigh,
                    identifier: "home-shuffle-button",
                    isDisabled: tracks.isEmpty,
                    action: { shuffleAll(playlist: playlist, tracks: tracks) }
                )
            }
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func playlistActionButton(
        title: String,
        systemImage: String,
        foreground: Color,
        background: Color,
        identifier: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.bounce)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityIdentifier(identifier)
    }

    private func playAll(playlist: Playlist?, tracks: [Track]) {
        guard let playlist, !tracks.isEmpty else { return }
        Task {
            playbackService.setPlaybackMode(.sequence)
            await playbackService.replaceQueue(tracks, activePlaylistID: playlist.id)
            toastCenter.show("已开始播放 \(tracks.count) 首歌曲")
        }
    }

    private func shuffleAll(playlist: Playlist?, tracks: [Track]) {
        guard let playlist, !tracks.isEmpty else { return }
        Task {
            _ = await playbackService.shuffleAndPlay(tracks, activePlaylistID: playlist.id)
            toastCenter.show(tracks.count == 1 ? "已开始播放" : "已随机播放 \(tracks.count) 首歌曲")
        }
    }

    private func removeTrack(_ track: Track, from selectedPlaylist: Playlist? = nil) {
        guard let playlist = selectedPlaylist ?? personalPlaylist,
              let index = playlist.orderedItems.firstIndex(where: { $0.track.musicId == track.musicID }) else { return }
        do {
            try LibraryStore(context: modelContext).removeItem(at: index, from: playlist)
            playbackService.onTrackRemovedFromPlaylist(track, playlistID: playlist.id)
            toastCenter.show("已从歌单移出")
            AppHaptics.medium()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func refreshTrackDetails(_ candidates: [Track], limit: Int = 20, force: Bool = false) async {
        guard let trackDetailRefreshCoordinator else { return }
        let selected = force ? candidates : candidates.filter { $0.highestKnownQuality == .standard }
        guard !selected.isEmpty else { return }
        let store = LibraryStore(context: modelContext)

        for track in selected.prefix(limit) {
            if Task.isCancelled { return }
            do {
                let outcome = try await trackDetailRefreshCoordinator.refresh(track, store: store, force: force)
                if case let .refreshed(refreshed) = outcome {
                    try Task.checkCancellation()
                    playbackService.updateTrackMetadata(refreshed)
                }
            } catch is CancellationError {
                return
            } catch {
                // Existing metadata remains usable and the coordinator persists retry backoff.
            }
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
        }
    }
}

struct HomeSearchOverlay: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.sonarReduceMotion) private var reduceMotion

    @Bindable var model: SearchViewModel
    let focusOnAppear: Bool
    let onClose: () -> Void
    let onOpenArtist: (ArtistSummary) -> Void
    let onOpenPlaylist: (PlaylistSummary) -> Void
    @State private var selectedTrackForActions: Track?
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Button(action: closeSearch) {
                    Color.black.opacity(0.38)
                        .ignoresSafeArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭搜索")
                .accessibilityIdentifier("search-backdrop")
                .accessibilitySortPriority(-1)

                VStack(spacing: 10) {
                    searchBar
                    if !trimmedQuery.isEmpty {
                        VStack(spacing: 0) {
                            searchFilters
                            Divider().overlay(scheme.outlineVariant)
                            searchContent
                        }
                        .frame(maxHeight: min(max(proxy.size.height - 84, 0), 600))
                        .background(scheme.appSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.16), radius: 20, y: 8)
                        .foregroundStyle(scheme.onSurface)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
        }
        .animation(AppMotion.emphasized(duration: AppMotion.short, reduceMotion: reduceMotion), value: trimmedQuery.isEmpty)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, closeSearch)
        .onKeyPress(.escape) {
            closeSearch()
            return .handled
        }
        .onAppear {
            SearchStorageMigration.clearLegacyHistory()
            focused = focusOnAppear
        }
        .onDisappear {
            focused = false
            model.cancelLiveSearch()
        }
        .onChange(of: model.query) { _, _ in model.liveSearch() }
        .confirmationDialog(
            selectedTrackForActions.map { "\($0.title)" } ?? "歌曲操作",
            isPresented: Binding(
                get: { selectedTrackForActions != nil },
                set: { if !$0 { selectedTrackForActions = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("立即播放", systemImage: "play.fill") {
                guard let track = selectedTrackForActions else { return }
                selectedTrackForActions = nil
                Task { await playbackService.replaceQueue([track]) }
            }
            Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") {
                guard let track = selectedTrackForActions else { return }
                selectedTrackForActions = nil
                Task {
                    await playbackService.playNext(track)
                    toastCenter.show("已设为下一首播放")
                }
            }
            Button("加入待播放", systemImage: "text.badge.plus") {
                guard let track = selectedTrackForActions else { return }
                selectedTrackForActions = nil
                Task {
                    let added = await playbackService.enqueue(track)
                    toastCenter.show(added ? "已加入待播放" : "歌曲已在待播放中")
                }
            }
            Button("收藏到歌单", systemImage: "music.note.list") {
                guard let track = selectedTrackForActions else { return }
                selectedTrackForActions = nil
                PersonalPlaylistCollectionFeedback.collect(
                    track,
                    context: modelContext,
                    toastCenter: toastCenter,
                    playbackService: playbackService
                )
            }
            Button("取消", role: .cancel) { selectedTrackForActions = nil }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                TextField("搜索歌曲、歌手或歌单", text: $model.query)
                    .font(.system(size: 15))
                    .foregroundStyle(scheme.onSurface)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit(submitSearch)
                    .accessibilityIdentifier("search-field")
                if !model.query.isEmpty {
                    Button(action: clearSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空")
                    .accessibilityIdentifier("search-clear-button")
                }
            }
            .foregroundStyle(scheme.onSurfaceVariant)
            .padding(.leading, 16)
            .padding(.trailing, model.query.isEmpty ? 12 : 0)
            .frame(minHeight: 52)

            Button(action: closeSearch) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(scheme.onSurfaceVariant)
            .buttonStyle(.plain)
            .accessibilityLabel("取消搜索")
            .accessibilityIdentifier("search-cancel-button")
        }
        .padding(.trailing, 4)
        .background(scheme.appSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(scheme.outlineVariant, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 4)
    }

    @ViewBuilder
    private var searchContent: some View {
        if model.hasSearched {
            searchResultsContent
        } else {
            ProgressView("正在搜索…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var searchFilters: some View {
        HStack(spacing: 12) {
            searchScopePicker
            if model.selectedScope == .songs {
                searchSourcePicker
            } else {
                Text("QQ 音乐")
                    .font(.caption)
                    .foregroundStyle(scheme.onSurfaceVariant)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var searchScopePicker: some View {
        HStack(spacing: 0) {
            ForEach(SearchScope.allCases) { scope in
                Button {
                    focused = false
                    model.selectedScope = scope
                    Task { await model.loadScopeIfNeeded(scope) }
                } label: {
                    Text(scope.rawValue)
                        .font(.system(size: 14, weight: model.selectedScope == scope ? .semibold : .regular))
                        .foregroundStyle(scheme.onSurface)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if model.selectedScope == scope {
                                Capsule().fill(scheme.appSurface)
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 3)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.selectedScope == scope ? .isSelected : [])
                .accessibilityIdentifier("search-scope-\(scope.id)")
            }
        }
        .background(scheme.appInputFill, in: Capsule())
    }

    private var searchSourcePicker: some View {
        Menu {
            Picker("歌曲音源", selection: Binding(
                get: { model.selectedSongSource },
                set: { source in
                    focused = false
                    Task { await model.selectSongSource(source) }
                }
            )) {
                ForEach(MusicSource.allCases, id: \.self) { source in
                    Text(source.displayName).tag(source)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.selectedSongSource.displayName)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(scheme.onSurfaceVariant)
            .frame(minHeight: 44)
        }
        .accessibilityLabel("歌曲音源：\(model.selectedSongSource.displayName)")
        .accessibilityHint("切换 QQ 音乐或网易云")
        .accessibilityIdentifier("search-source-picker")
    }

    private var searchResultsContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch model.selectedScope {
                case .songs:
                    songsResultSection
                case .artists:
                    artistsResultSection
                case .playlists:
                    playlistsResultSection
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var songsResultSection: some View {
        VStack(spacing: 0) {
            if model.isLoading || !model.hasLoadedSongs {
                ProgressView("正在搜索歌曲…")
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityIdentifier("search-song-loading")
            } else if let errorMessage = model.songSearchErrorMessage ?? model.errorMessage {
                VStack {
                    ContentUnavailableView("搜索不可用", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                    Button(model.isRetryingFailedSource ? "正在重试…" : "重试\(model.selectedSongSource.displayName)搜索") {
                        Task { await model.retryFailedSource() }
                    }
                    .disabled(model.isRetryingFailedSource)
                    .accessibilityIdentifier("search-song-retry")
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if model.results.isEmpty {
                ContentUnavailableView("未找到歌曲", systemImage: "music.note.list")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ForEach(Array(model.results.enumerated()), id: \.element.musicID) { index, track in
                    SongRow(
                        track: track,
                        trailing: .more,
                        showDivider: index < model.results.count - 1,
                        isCurrent: playbackService.queue.current?.musicID == track.musicID,
                        isPlaying: playbackService.state == .playing,
                        onPlay: {
                            focused = false
                            Task { await playbackService.replaceQueue([track]) }
                        },
                        onAction: {
                            focused = false
                            selectedTrackForActions = track
                        }
                    )
                }
            }
        }
    }

    private var artistsResultSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isLoadingArtists || !model.hasLoadedArtists {
                ProgressView("正在搜索歌手…")
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityIdentifier("search-artist-loading")
            } else if model.artistResults.isEmpty && !model.failedArtistSources.isEmpty {
                ContentUnavailableView(
                    "歌手搜索暂不可用",
                    systemImage: "exclamationmark.triangle",
                    description: Text("请检查网络后重试")
                )
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if model.artistResults.isEmpty {
                ContentUnavailableView("未找到歌手", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ForEach(model.visibleArtistResults, id: \.stableID) { artist in
                    Button {
                        focused = false
                        onOpenArtist(artist)
                    } label: {
                        HStack(spacing: 14) {
                            RemotePlaylistArtwork(urlString: artist.imageURL)
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(artist.name)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(scheme.onSurface)
                                        .lineLimit(1)

                                    Text("歌手")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(scheme.primary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(scheme.primary.opacity(0.12), in: Capsule())
                                }

                                Text(artistMetadata(artist))
                                    .font(.caption)
                                    .foregroundStyle(scheme.onSurfaceVariant)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(scheme.outline)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 68)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.cellHighlight)
                    .accessibilityIdentifier("search-artist-\(artist.stableID)")
                }

                ForEach(model.artistSourceWarnings, id: \.self) { source in
                    artistWarning(source: source, isExpansion: false)
                }

                if model.isArtistResultsExpanded {
                    ForEach(model.artistExpansionWarnings, id: \.self) { source in
                        artistWarning(source: source, isExpansion: true)
                    }
                }

                artistExpansionFooter
            }
        }
    }

    private var playlistsResultSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isLoadingPlaylists || !model.hasLoadedPlaylists {
                ProgressView("正在搜索歌单…")
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityIdentifier("search-playlist-loading")
            } else if let errorMessage = model.playlistErrorMessage {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "歌单搜索暂不可用",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                    Button {
                        Task { await model.retryPlaylistSearch() }
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(scheme.primary)
                    .accessibilityLabel("重试QQ 音乐歌单搜索")
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if model.playlistResults.isEmpty {
                ContentUnavailableView("未找到歌单", systemImage: "music.note.list")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ForEach(model.playlistResults, id: \.key) { playlist in
                    Button {
                        focused = false
                        onOpenPlaylist(playlist)
                    } label: {
                        HStack(spacing: 14) {
                            RemotePlaylistArtwork(urlString: playlist.img)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(playlist.name)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(scheme.onSurface)
                                    .lineLimit(2)
                                Text(playlist.author.isEmpty ? "QQ 音乐歌单" : playlist.author)
                                    .font(.caption)
                                    .foregroundStyle(scheme.onSurfaceVariant)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(scheme.outline)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 76)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.cellHighlight)
                    .accessibilityIdentifier("search-playlist-\(playlist.key)")
                }
            }
        }
    }

    @ViewBuilder
    private var artistExpansionFooter: some View {
        if !model.isArtistResultsExpanded, model.canExpandArtistResults {
            Button {
                Task { await model.expandArtistResults() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                    Text(artistExpansionTitle)
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(scheme.primary)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("展开后才会继续请求剩余歌手")
            .accessibilityIdentifier("search-artist-expand")
        } else if model.isArtistResultsExpanded {
            if model.isLoadingMoreArtists {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在加载更多歌手…")
                        .font(.caption)
                    Spacer()
                }
                .foregroundStyle(scheme.onSurfaceVariant)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .accessibilityIdentifier("search-artist-loading-more")
            } else if model.canExpandArtistResults, model.artistExpansionWarnings.isEmpty {
                Button {
                    Task { await model.loadMoreArtists() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 14, weight: .semibold))
                        Text("继续加载剩余 \(model.artistRemainingCount) 位歌手")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(scheme.primary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search-artist-load-more")
            }

            Button {
                model.collapseArtistResults()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                    Text("收起歌手列表")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(scheme.onSurfaceVariant)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search-artist-collapse")
        }
    }

    private var artistExpansionTitle: String {
        let remaining = model.artistRemainingCount
        return remaining > 0 ? "查看剩余 \(remaining) 位歌手" : "查看更多歌手"
    }

    private func artistWarning(source: MusicSource, isExpansion: Bool) -> some View {
        let isRetrying = isExpansion
            ? model.retryingArtistExpansionSources.contains(source)
            : model.retryingArtistSources.contains(source)
        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(scheme.primary)
            Text(isExpansion ? "\(source.displayName) 更多歌手加载暂不可用" : "\(source.displayName)歌手搜索暂不可用")
                .font(.caption)
                .foregroundStyle(scheme.onSurfaceVariant)
                .lineLimit(2)
            Spacer()
            Button {
                Task {
                    if isExpansion {
                        await model.retryArtistExpansion(source)
                    } else {
                        await model.retryArtistSource(source)
                    }
                }
            } label: {
                if isRetrying {
                    ProgressView().controlSize(.small).frame(width: 44, height: 44)
                } else {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }
            }
            .buttonStyle(.plain)
            .disabled(isRetrying)
            .accessibilityLabel(isExpansion ? "重试加载更多\(source.displayName)歌手" : "重试\(source.displayName)歌手搜索")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: 48)
        .accessibilityIdentifier(
            isExpansion ? "search-artist-load-more-retry-\(source.rawValue)" : "search-artist-retry-\(source.rawValue)"
        )
    }

    private func artistMetadata(_ artist: ArtistSummary) -> String {
        var values: [String] = []
        if let count = artist.songCount, count > 0 { values.append("\(count) 首歌曲") }
        if let count = artist.albumCount, count > 0 { values.append("\(count) 张专辑") }
        return values.joined(separator: " · ")
    }

    private var trimmedQuery: String {
        model.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearSearch() {
        model.cancelLiveSearch()
        model.query = ""
        model.selectedScope = .songs
        model.queryChanged()
        focused = true
    }

    private func closeSearch() {
        focused = false
        onClose()
    }

    private func submitSearch() {
        model.cancelLiveSearch()
        guard !trimmedQuery.isEmpty else { return }
        focused = false
        Task { await model.search() }
    }

}

struct RemotePlaylistArtwork: View {
    @Environment(\.m3Scheme) private var scheme
    let urlString: String?

    private var url: URL? {
        guard let urlString, !urlString.isEmpty else { return nil }
        if urlString.hasPrefix("//") { return URL(string: "https:\(urlString)") }
        guard var components = URLComponents(string: urlString) else { return nil }
        if components.scheme?.lowercased() == "http" { components.scheme = "https" }
        return components.url
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image): image.resizable().scaledToFill()
            case .failure: placeholder(systemImage: "exclamationmark.triangle")
            case .empty: placeholder(systemImage: "music.note")
            @unknown default: placeholder(systemImage: "music.note")
            }
        }
        .clipped()
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            scheme.surfaceContainerHigh
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(scheme.onSurfaceVariant)
        }
    }
}

struct RemotePlaylistDetailView: View {
    let playlist: PlaylistSummary
    private let runtime: SourceRuntime

    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var model: HomeFreshFeedViewModel

    init(playlist: PlaylistSummary, runtime: SourceRuntime) {
        self.playlist = playlist
        self.runtime = runtime
        _model = State(initialValue: HomeFreshFeedViewModel(runtime: runtime))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
                Spacer()
                Text("QQ 音乐歌单")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .foregroundStyle(scheme.onSurface)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        RemotePlaylistArtwork(urlString: playlist.img)
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(playlist.name)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(scheme.onSurface)
                                .lineLimit(3)
                            Text(playlist.author.isEmpty ? "QQ 音乐" : playlist.author)
                                .font(.subheadline)
                                .foregroundStyle(scheme.onSurfaceVariant)
                                .lineLimit(1)
                            if let total = playlist.total, total > 0 {
                                Text("\(total) 首歌曲")
                                    .font(.caption)
                                    .foregroundStyle(scheme.onSurfaceVariant)
                            }
                        }
                    }
                    .padding(16)

                    if model.isLoading && model.tracks.isEmpty {
                        ProgressView("正在加载歌单…")
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else if let errorMessage = model.errorMessage, model.tracks.isEmpty {
                        ContentUnavailableView("歌单暂不可用", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                    } else if !model.tracks.isEmpty {
                        Button {
                            Task { await playbackService.replaceQueue(model.tracks) }
                        } label: {
                            Label("播放全部", systemImage: "play.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                        ForEach(Array(model.tracks.enumerated()), id: \.element.musicID) { index, track in
                            SongRow(
                                track: track,
                                trailing: .more,
                                showDivider: index < model.tracks.count - 1,
                                isCurrent: playbackService.queue.current?.musicID == track.musicID,
                                isPlaying: playbackService.state == .playing,
                                onPlay: { Task { await playbackService.replaceQueue(model.tracks, startingAt: index) } },
                                onAction: {}
                            )
                            .onAppear {
                                if index == model.tracks.count - 1 {
                                    Task { await model.loadMoreIfNeeded() }
                                }
                            }
                        }

                        if model.isLoadingMore {
                            ProgressView("正在加载更多…")
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task { await model.loadInitialIfNeeded(from: playlist) }
    }
}
