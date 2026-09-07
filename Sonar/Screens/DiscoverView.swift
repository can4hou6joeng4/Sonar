import SwiftData
import SwiftUI

struct DiscoverView: View {
    let isActive: Bool
    let onOpenSettings: () -> Void
    let onSettingsDragChanged: (DragGesture.Value) -> Void
    let onSettingsDragEnded: (DragGesture.Value) -> Void
    private let runtime: SourceRuntime

    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme
    @Query(sort: \Playlist.sortIndex) private var libraryPlaylists: [Playlist]
    @State private var actionError: String?
    @State private var personalPlaylistIsPresented = false
    @State private var selectedTrackForActions: Track?

    init(
        runtime: SourceRuntime,
        isActive: Bool,
        onOpenSettings: @escaping () -> Void = {},
        onSettingsDragChanged: @escaping (DragGesture.Value) -> Void = { _ in },
        onSettingsDragEnded: @escaping (DragGesture.Value) -> Void = { _ in }
    ) {
        self.isActive = isActive
        self.onOpenSettings = onOpenSettings
        self.onSettingsDragChanged = onSettingsDragChanged
        self.onSettingsDragEnded = onSettingsDragEnded
        self.runtime = runtime
    }

    private var personalPlaylist: Playlist? {
        libraryPlaylists.first {
            $0.isPrimaryPersonal && !$0.isArchived && !$0.isSystem && $0.kind == .music
        }
    }

    private var tracks: [Track] {
        personalPlaylist?.orderedItems.compactMap { $0.track.track } ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            homeContent
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .rootSettingsDrawerGesture(
            isEnabled: isActive,
            onOpen: onOpenSettings,
            onChanged: onSettingsDragChanged,
            onEnded: onSettingsDragEnded
        )
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $personalPlaylistIsPresented) {
            if let personalPlaylist {
                PlaylistDetailView(
                    playlist: personalPlaylist,
                    onBack: { personalPlaylistIsPresented = false }
                )
            } else {
                SongsView(isActive: false)
            }
        }
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
            NavigationLink {
                NCMSearchView(runtime: runtime)
            } label: {
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

    private var homeContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                personalPlaylistCard

                if !tracks.isEmpty {
                    HStack {
                        Text("歌曲 (\(tracks.count))")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(scheme.onSurface)

                        Spacer()

                        HStack(spacing: 8) {
                            Button {
                                Task {
                                    if playbackService.playbackMode == .shuffle {
                                        await playbackService.shuffleAndPlay(tracks, activePlaylistID: personalPlaylist?.id)
                                    } else {
                                        await playbackService.replaceQueue(tracks, startingAt: 0, activePlaylistID: personalPlaylist?.id)
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 11))
                                    Text("播放全部")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(scheme.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(scheme.primary.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home-play-all-button")

                            Button {
                                Task {
                                    await playbackService.shuffleAndPlay(tracks, activePlaylistID: personalPlaylist?.id)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "shuffle")
                                        .font(.system(size: 11))
                                    Text("随机播放")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(scheme.onSurfaceVariant)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(scheme.surfaceContainerHigh, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home-shuffle-button")
                        }
                    }
                    .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 6)

                    ForEach(Array(tracks.enumerated()), id: \.element.musicID) { index, track in
                        SongRow(
                            track: track,
                            leading: .cover,
                            trailing: .more,
                            showDivider: index < tracks.count - 1,
                            isCurrent: playbackService.queue.current?.musicID == track.musicID,
                            isPlaying: playbackService.state == .playing,
                            onPlay: { Task { await playbackService.replaceQueue(tracks, startingAt: index, activePlaylistID: personalPlaylist?.id) } },
                            onAction: { selectedTrackForActions = track }
                        )
                        .contextMenu {
                            Button {
                                Task { await playbackService.replaceQueue(tracks, startingAt: index, activePlaylistID: personalPlaylist?.id) }
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
                                removeTrack(track)
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
    }

    private var personalPlaylistCard: some View {
        Button {
            personalPlaylistIsPresented = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(scheme.primary.opacity(0.12))
                        .frame(width: 60, height: 60)

                    if let firstTrack = personalPlaylist?.orderedItems.first?.track.track {
                        PlayerArtwork(track: firstTrack, size: 60, cornerRadius: 12)
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    } else {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(scheme.primary)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("我喜欢的音乐")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(scheme.onSurface)
                        .lineLimit(1)

                    Text("\(personalPlaylist?.orderedItems.count ?? 0) 首歌曲")
                        .font(.system(size: 13))
                        .foregroundStyle(scheme.onSurfaceVariant)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(scheme.onSurfaceVariant.opacity(0.6))
                    .padding(.trailing, 4)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(scheme.surfaceContainerLow)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .buttonStyle(.bounce)
        .accessibilityIdentifier("home-personal-playlist-card")
    }

    private func removeTrack(_ track: Track) {
        guard let playlist = personalPlaylist,
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
}

private struct NCMSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.m3Scheme) private var scheme

    @State private var model: SearchViewModel
    @State private var selectedTrackForActions: Track?
    @FocusState private var focused: Bool
    private let runtime: SourceRuntime

    init(runtime: SourceRuntime) {
        self.runtime = runtime
        _model = State(initialValue: SearchViewModel(runtime: runtime))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            searchContent
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .ncmEdgeSwipeBack()
        .onAppear {
            SearchStorageMigration.clearLegacyHistory()
            focused = true
        }
        .task { await model.loadHotSearchesIfNeeded() }
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
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                TextField("搜索歌曲、歌手或专辑", text: $model.query)
                    .font(.system(size: 15))
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
                }
            }
            .foregroundStyle(scheme.onSurfaceVariant)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(scheme.appInputFill, in: Capsule())

            Button("取消") {
                if model.query.isEmpty {
                    dismiss()
                } else {
                    clearSearch()
                    focused = true
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(scheme.onSurface)
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier("search-cancel-button")
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .onChange(of: model.query) { _, _ in
            model.liveSearch()
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if trimmedQuery.isEmpty {
            hotSearchContent
        } else if model.isLoading {
            ProgressView("正在搜索…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage {
            ContentUnavailableView("搜索不可用", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if model.hasSearched, model.results.isEmpty, model.artistResults.isEmpty {
            ContentUnavailableView("未找到结果", systemImage: "music.note.list")
        } else if model.hasSearched {
            searchResultsContent
        } else {
            ProgressView("正在搜索…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var hotSearchContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("热门搜索")
                        .font(.system(size: 17, weight: .bold))
                    Spacer()
                    if model.isLoadingHotSearches {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在更新热门搜索")
                    } else if let errorMessage = model.hotSearchErrorMessage {
                        Button {
                            Task { await model.refreshHotSearches() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(scheme.onSurfaceVariant)
                        .accessibilityLabel("重新加载热门搜索")
                        .accessibilityHint(errorMessage)
                        .accessibilityIdentifier("search-hot-retry")
                    }
                }
                .frame(minHeight: 44)

                rankedHotSearchRows(model.hotSearches, identifierPrefix: "search-hot")
            }
            .foregroundStyle(scheme.onSurface)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.refreshHotSearches() }
    }

    private var searchResultsContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !model.artistResults.isEmpty || !model.artistSourceWarnings.isEmpty {
                    artistResultsSection
                }

                ForEach(Array(model.results.enumerated()), id: \.element.musicID) { index, track in
                    SongRow(
                        track: track,
                        trailing: .more,
                        showDivider: index < model.results.count - 1,
                        isCurrent: playbackService.queue.current?.musicID == track.musicID,
                        isPlaying: playbackService.state == .playing,
                        onPlay: { Task { await playbackService.replaceQueue([track]) } },
                        onAction: { selectedTrackForActions = track }
                    )
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var artistResultsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("歌手")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(scheme.onSurface)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("search-artist-section")

            ForEach(model.visibleArtistResults, id: \.stableID) { artist in
                NavigationLink {
                    ArtistDetailView(artist: artist, runtime: runtime)
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

            Rectangle().fill(scheme.outlineVariant).frame(height: 0.5).padding(.leading, 16)

            if !model.results.isEmpty {
                Text("歌曲")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(scheme.onSurface)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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

    private var searchDivider: some View {
        Rectangle()
            .fill(scheme.outlineVariant)
            .frame(height: 0.5)
            .padding(.leading, 42)
    }

    private func rankedHotSearchRows(_ values: [String], identifierPrefix: String) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Button {
                    model.query = value
                    submitSearch()
                } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(index < 3 ? scheme.primary : scheme.onSurfaceVariant)
                            .frame(width: 20, alignment: .trailing)
                        Text(value)
                            .font(.system(size: 15))
                            .foregroundStyle(scheme.onSurface)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(identifierPrefix)-\(index + 1)")
            }
        }
    }

    private var trimmedQuery: String {
        model.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearSearch() {
        model.cancelLiveSearch()
        model.query = ""
        model.queryChanged()
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

extension PlaylistSummary {
    var key: String { "\(source.rawValue):\(id)" }
}

extension Track: Identifiable {
    public var id: String { musicID }
}
