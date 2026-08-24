import SwiftData
import SwiftUI

struct DiscoverView: View {
    let isActive: Bool
    private let runtime: SourceRuntime

    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.sonarReduceMotion) private var reduceMotion

    @Query(sort: \TrackRecord.title) private var allRecords: [TrackRecord]
    @Query(filter: #Predicate<Playlist> { !$0.isSystem }, sort: \Playlist.sortIndex)
    private var playlists: [Playlist]

    @State private var discoveryModel: DiscoveryViewModel
    @State private var bannerIndex = 0
    @State private var freshTracks: [Track] = []
    @State private var recentTracks: [Track] = []
    @State private var freshError: String?
    @State private var isLoadingFresh = false
    @State private var playingPlaylistKey: String?
    @State private var likedPlaylist: Playlist?
    @State private var actionError: String?
    @State private var showPlaylistSquare = false
    @State private var showRecent = false
    @State private var showLocal = false
    @State private var showLiked = false
    @State private var showPlaylists = false
    @State private var showQuality = false
    @State private var showSettings = false

    init(runtime: SourceRuntime, isActive: Bool) {
        self.isActive = isActive
        self.runtime = runtime
        _discoveryModel = State(initialValue: DiscoveryViewModel(runtime: runtime))
    }

    private var playlistsBySource: [MusicSource: [PlaylistSummary]] {
        Dictionary(uniqueKeysWithValues: MusicSource.allCases.map {
            ($0, discoveryModel.state(for: $0).items)
        })
    }

    private var mergedPlaylists: [PlaylistSummary] {
        DiscoveryContent.merged(playlistsBySource)
    }

    private var banners: [PlaylistSummary] { Array(mergedPlaylists.prefix(3)) }
    private var featured: [PlaylistSummary] { Array(mergedPlaylists.prefix(8)) }

    private var isInitialLoading: Bool {
        MusicSource.allCases.contains { discoveryModel.state(for: $0).isLoading }
    }

    private var initialErrors: [String] {
        MusicSource.allCases.compactMap { discoveryModel.state(for: $0).errorMessage }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            homeContent
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showPlaylistSquare) {
            PlaylistSquareView(model: discoveryModel, runtime: runtime)
        }
        .navigationDestination(isPresented: $showRecent) {
            PlaylistDetailView(
                title: "最近播放",
                subtitle: "最近播放",
                description: "按最近成功播放的顺序排列。",
                tracks: recentTracks
            )
        }
        .navigationDestination(isPresented: $showLiked) {
            if let likedPlaylist {
                PlaylistDetailView(playlist: likedPlaylist)
            } else {
                ContentUnavailableView("无法打开我喜欢", systemImage: "heart.slash")
            }
        }
        .navigationDestination(isPresented: $showPlaylists) {
            PlaylistsView(playlists: playlists)
        }
        .sheet(isPresented: $showLocal) {
            NavigationStack { LocalSongsView() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showQuality) {
            QualitySheet(track: playbackService.queue.current)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.large])
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
        .task {
            await loadCatalogs()
            loadRecentTracks()
        }
        .task(id: mergedPlaylists.first?.key) { await loadFreshTracks() }
        .task(id: banners.map(\.key).joined(separator: "|")) { await rotateBanners() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("首页")
                .font(.system(size: NCMDesignTokens.Typography.homeTitle, weight: .bold))
                .foregroundStyle(scheme.onSurface)
            Spacer()
            NavigationLink {
                NCMSearchView(runtime: runtime)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(scheme.onSurface)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("搜索")
            .accessibilityIdentifier("home-search-button")
        }
        .frame(minHeight: NCMDesignTokens.Layout.navigationHeight)
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var homeContent: some View {
        if mergedPlaylists.isEmpty, isInitialLoading {
            ProgressView("正在加载首页…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if mergedPlaylists.isEmpty, !initialErrors.isEmpty {
            ContentUnavailableView {
                Label("首页加载失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(initialErrors.first ?? "网络不可用")
            } actions: {
                Button("重试") { Task { await refreshCatalogs() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    bannerSection
                    shortcuts
                    featuredSection
                    freshSection
                    if !recentTracks.isEmpty { recentSection }
                    Color.clear.frame(height: 28)
                }
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await refreshCatalogs()
                loadRecentTracks()
            }
        }
    }

    @ViewBuilder
    private var bannerSection: some View {
        if !banners.isEmpty {
            let index = min(bannerIndex, banners.count - 1)
            let banner = banners[index]
            NavigationLink {
                OnlinePlaylistDetailView(playlist: banner, runtime: runtime)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    RemotePlaylistArtwork(urlString: banner.img)
                        .frame(maxWidth: .infinity)
                        .frame(height: NCMDesignTokens.Layout.bannerHeight)
                    LinearGradient(
                        colors: [.black.opacity(0.62), .black.opacity(0.30), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(banner.name)
                            .font(.system(size: NCMDesignTokens.Typography.bannerTitle, weight: .bold))
                            .lineLimit(1)
                        Text(bannerSubtitle(for: banner))
                            .font(.system(size: NCMDesignTokens.Typography.bannerSubtitle))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: NCMDesignTokens.Layout.bannerCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-banner-\(banner.key)")
            .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
            .padding(.top, 6)

            NCMPagingDots(count: banners.count, selected: index)
                .padding(.top, 7)
        }
    }

    private var shortcuts: some View {
        let items: [(String, String, String)] = [
            ("square", "歌单广场", "square.grid.2x2"),
            ("recent", "最近播放", "clock.arrow.circlepath"),
            ("local", "本地歌曲", "music.note.list"),
            ("liked", "我喜欢", "heart"),
            ("playlists", "我的歌单", "text.badge.plus"),
            ("shuffle", "随机播放", "shuffle"),
            ("quality", "音质", "slider.horizontal.3"),
            ("settings", "设置", "gearshape"),
        ]
        return VStack(spacing: NCMDesignTokens.Layout.shortcutSpacing) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: NCMDesignTokens.Layout.shortcutSpacing) {
                    ForEach(Array(items[(row * 4)..<(row * 4 + 4)]), id: \.0) { item in
                        Button { openShortcut(item.0) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: item.2)
                                    .font(.system(size: 17, weight: .regular))
                                Text(item.1)
                                    .font(.system(size: NCMDesignTokens.Typography.shortcut, weight: .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.88)
                            }
                            .foregroundStyle(scheme.onSurface)
                            .frame(maxWidth: .infinity)
                            .frame(height: NCMDesignTokens.Layout.shortcutHeight)
                            .background(
                                scheme.surfaceContainer,
                                in: RoundedRectangle(cornerRadius: NCMDesignTokens.Layout.shortcutCornerRadius, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home-shortcut-\(item.0)")
                    }
                }
            }
            NCMPagingDots(count: 2, selected: 0)
                .padding(.top, 1)
        }
        .padding(.horizontal, 15)
        .padding(.top, 14)
    }

    private var featuredSection: some View {
        VStack(spacing: 0) {
            NCMSectionHeader(title: "甄选歌单", action: "更多") { showPlaylistSquare = true }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(featured, id: \.key) { playlist in
                        NCMPlaylistCard(
                            playlist: playlist,
                            runtime: runtime,
                            isLoading: playingPlaylistKey == playlist.key,
                            onPlay: { playPlaylist(playlist) }
                        )
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        }
    }

    private var freshSection: some View {
        VStack(spacing: 0) {
            NCMSectionHeader(title: "新歌新碟", action: "更多") { showLocal = true }
            if isLoadingFresh, freshTracks.isEmpty {
                ForEach(0..<4, id: \.self) { _ in NCMHomeSongSkeleton() }
            } else if let freshError, freshTracks.isEmpty {
                Button { Task { await loadFreshTracks() } } label: {
                    Label("加载失败，点击重试", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(scheme.onSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.plain)
                .accessibilityHint(freshError)
            } else {
                ForEach(Array(freshTracks.prefix(4).enumerated()), id: \.element.musicID) { index, track in
                    NCMHomeSongRow(
                        track: track,
                        isCurrent: playbackService.queue.current?.musicID == track.musicID,
                        isPlaying: playbackService.state == .playing,
                        showDivider: index < min(freshTracks.count, 4) - 1,
                        onPlay: { Task { await playbackService.replaceQueue(freshTracks, startingAt: index) } }
                    )
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(spacing: 0) {
            NCMSectionHeader(title: "最近播放", action: "更多") { showRecent = true }
            ForEach(Array(recentTracks.prefix(3).enumerated()), id: \.element.musicID) { index, track in
                NCMHomeSongRow(
                    track: track,
                    isCurrent: playbackService.queue.current?.musicID == track.musicID,
                    isPlaying: playbackService.state == .playing,
                    showDivider: index < min(recentTracks.count, 3) - 1,
                    onPlay: { Task { await playbackService.replaceQueue(recentTracks, startingAt: index) } }
                )
            }
        }
    }

    private func bannerSubtitle(for playlist: PlaylistSummary) -> String {
        let author = playlist.author.trimmingCharacters(in: .whitespacesAndNewlines)
        return [author.isEmpty ? nil : author, playlist.playCount.isEmpty ? nil : "\(playlist.playCount) 次播放"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func loadCatalogs() async {
        for source in MusicSource.allCases { await discoveryModel.loadInitial(for: source) }
    }

    private func refreshCatalogs() async {
        for source in MusicSource.allCases { await discoveryModel.refresh(source) }
    }

    private func loadFreshTracks() async {
        guard let playlist = mergedPlaylists.first else {
            freshTracks = []
            return
        }
        isLoadingFresh = true
        freshError = nil
        defer { isLoadingFresh = false }
        do {
            let detail = try await runtime.playlistDetail(source: playlist.source, id: playlist.id, page: 1)
            freshTracks = Array(DiscoveryContent.deduplicatedTracks(detail.list).prefix(4))
        } catch is CancellationError {
            return
        } catch {
            freshError = error.localizedDescription
        }
    }

    private func loadRecentTracks() {
        do {
            recentTracks = try LibraryStore(context: modelContext).recentTracks()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func rotateBanners() async {
        bannerIndex = 0
        guard banners.count > 1 else { return }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(5.2)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.emphasized(duration: AppMotion.medium, reduceMotion: reduceMotion)) {
                bannerIndex = (bannerIndex + 1) % banners.count
            }
        }
    }

    private func playPlaylist(_ playlist: PlaylistSummary) {
        guard playingPlaylistKey == nil else { return }
        playingPlaylistKey = playlist.key
        Task {
            defer { playingPlaylistKey = nil }
            do {
                let model = OnlinePlaylistDetailViewModel(playlist: playlist, runtime: runtime)
                let tracks = try await model.allTracks()
                guard !tracks.isEmpty else {
                    actionError = "这个歌单还没有可播放的曲目"
                    return
                }
                await playbackService.replaceQueue(tracks)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func openShortcut(_ key: String) {
        switch key {
        case "square": showPlaylistSquare = true
        case "recent":
            loadRecentTracks()
            showRecent = true
        case "local": showLocal = true
        case "liked": openLikedPlaylist()
        case "playlists": showPlaylists = true
        case "shuffle": playShuffledLibrary()
        case "quality": showQuality = true
        case "settings": showSettings = true
        default: break
        }
    }

    private func openLikedPlaylist() {
        do {
            let store = LibraryStore(context: modelContext)
            likedPlaylist = try store.playlists(includeSystem: false).first { $0.name == "我喜欢" }
                ?? store.createPlaylist(named: "我喜欢")
            showLiked = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func playShuffledLibrary() {
        var seen = Set<String>()
        let tracks = allRecords.compactMap(\.track).filter { seen.insert($0.musicID).inserted }.shuffled()
        guard !tracks.isEmpty else {
            actionError = "曲库里还没有歌曲，先搜索并播放一首歌。"
            return
        }
        Task { await playbackService.replaceQueue(tracks) }
    }
}

private struct NCMSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme

    @State private var model: SearchViewModel
    @State private var history = NCMSearchHistory.load()
    @State private var selectedTrackForPlaylist: Track?
    @FocusState private var focused: Bool

    private let hotSearches = ["晴天", "一路向北", "起风了", "海阔天空", "稻香", "富士山下"]

    init(runtime: SourceRuntime) {
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
        .onAppear { focused = true }
        .sheet(item: $selectedTrackForPlaylist) { track in
            AddToPlaylistSheet(track: track)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空")
                }
            }
            .foregroundStyle(scheme.onSurfaceVariant)
            .padding(.horizontal, 12)
            .frame(height: 36)
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
        .onChange(of: model.query) { _, _ in model.queryChanged() }
    }

    @ViewBuilder
    private var searchContent: some View {
        if model.query.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !history.isEmpty {
                        HStack {
                            Text("搜索历史").font(.system(size: 17, weight: .bold))
                            Spacer()
                            Button("清空") {
                                history.removeAll()
                                NCMSearchHistory.save(history)
                            }
                                .font(.system(size: 13))
                                .foregroundStyle(scheme.onSurfaceVariant)
                        }
                        chipGrid(history)
                    }
                    Text("热门搜索").font(.system(size: 17, weight: .bold))
                    LazyVStack(spacing: 0) {
                        ForEach(Array(hotSearches.enumerated()), id: \.element) { index, value in
                            Button {
                                model.query = value
                                submitSearch()
                            } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(index < 3 ? scheme.primary : scheme.onSurfaceVariant)
                                        .frame(width: 16, alignment: .trailing)
                                    Text(value)
                                        .font(.system(size: 15))
                                        .foregroundStyle(scheme.onSurface)
                                    Spacer(minLength: 0)
                                }
                                .frame(height: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .foregroundStyle(scheme.onSurface)
                .padding(16)
            }
        } else if !model.suggestions.isEmpty && !model.hasSearched {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.suggestions, id: \.self) { suggestion in
                        Button {
                            model.query = suggestion
                            submitSearch()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(scheme.onSurfaceVariant)
                                highlightedSuggestion(suggestion)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 46)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(scheme.outlineVariant).frame(height: 0.5).padding(.leading, 26)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if model.isLoading {
            ProgressView("正在搜索…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage {
            ContentUnavailableView("搜索不可用", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if model.hasSearched, model.results.isEmpty {
            ContentUnavailableView("未找到结果", systemImage: "music.note.list")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.results.enumerated()), id: \.element.musicID) { index, track in
                        SongRow(
                            track: track,
                            trailing: .more,
                            showDivider: index < model.results.count - 1,
                            isCurrent: playbackService.queue.current?.musicID == track.musicID,
                            isPlaying: playbackService.state == .playing,
                            onPlay: { Task { await playbackService.replaceQueue(model.results, startingAt: index) } },
                            onAction: { selectedTrackForPlaylist = track }
                        )
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func chipGrid(_ values: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                Button(value) {
                    model.query = value
                    submitSearch()
                }
                .font(.system(size: 13))
                .foregroundStyle(scheme.onSurface)
                .frame(height: 32)
                .padding(.horizontal, 14)
                .background(scheme.surfaceContainer, in: Capsule())
                .buttonStyle(.plain)
            }
        }
    }

    private func highlightedSuggestion(_ suggestion: String) -> Text {
        let query = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let range = suggestion.range(of: query, options: .caseInsensitive) else {
            return Text(suggestion).foregroundColor(scheme.onSurface)
        }
        return Text(String(suggestion[..<range.lowerBound])).foregroundColor(scheme.onSurface)
            + Text(String(suggestion[range])).foregroundColor(scheme.primary)
            + Text(String(suggestion[range.upperBound...])).foregroundColor(scheme.onSurface)
    }

    private func clearSearch() {
        model.query = ""
        model.queryChanged()
    }

    private func submitSearch() {
        let keyword = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        history.removeAll { $0 == keyword }
        history.insert(keyword, at: 0)
        history = Array(history.prefix(10))
        NCMSearchHistory.save(history)
        focused = false
        Task { await model.search() }
    }
}

private enum NCMSearchHistory {
    private static let key = "ncmSearchHistory"

    static func load(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    static func save(_ values: [String], defaults: UserDefaults = .standard) {
        defaults.set(values, forKey: key)
    }
}

private struct PlaylistSquareView: View {
    private enum Category: String, CaseIterable, Identifiable {
        case all = "全部"
        case hot = "最热"
        case new = "最新"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme

    let model: DiscoveryViewModel
    let runtime: SourceRuntime

    @State private var category: Category = .all
    @State private var playingPlaylistKey: String?
    @State private var actionError: String?

    private var merged: [PlaylistSummary] {
        let pages = Dictionary(uniqueKeysWithValues: MusicSource.allCases.map {
            ($0, model.state(for: $0).items)
        })
        let values = DiscoveryContent.merged(pages)
        switch category {
        case .all: return values
        case .hot:
            return values.sorted { DiscoveryContent.playCountValue($0.playCount) > DiscoveryContent.playCountValue($1.playCount) }
        case .new: return Array(values.reversed())
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
                Text("歌单广场").font(.system(size: 20, weight: .bold))
                Spacer()
            }
            .foregroundStyle(scheme.onSurface)
            .padding(.horizontal, 8)
            .padding(.top, 6)

            HStack(spacing: 26) {
                ForEach(Category.allCases) { value in
                    Button { category = value } label: {
                        Text(value.rawValue)
                            .font(.system(size: 16, weight: category == value ? .semibold : .regular))
                            .foregroundStyle(category == value ? scheme.onSurface : scheme.onSurfaceVariant)
                            .frame(height: 38)
                            .overlay(alignment: .bottom) {
                                if category == value { Capsule().fill(scheme.primary).frame(width: 22, height: 3) }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView {
                if merged.isEmpty {
                    ContentUnavailableView("暂无在线歌单", systemImage: "music.note.list")
                        .frame(minHeight: 420)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 16
                    ) {
                        ForEach(merged, id: \.key) { playlist in
                            NCMPlaylistGridCard(
                                playlist: playlist,
                                runtime: runtime,
                                isLoading: playingPlaylistKey == playlist.key,
                                onPlay: { playPlaylist(playlist) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    if MusicSource.allCases.contains(where: { model.state(for: $0).hasMore }) {
                        Button { Task { await loadMore() } } label: {
                            Label("加载更多", systemImage: "chevron.down")
                                .font(.system(size: 14, weight: .medium))
                                .frame(minWidth: 120, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(scheme.primary)
                        .padding(.vertical, 18)
                    }
                }
                Color.clear.frame(height: 120)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                for source in MusicSource.allCases { await model.refresh(source) }
            }
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .ncmEdgeSwipeBack()
        .alert("操作失败", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "未知错误")
        }
        .task {
            for source in MusicSource.allCases { await model.loadInitial(for: source) }
        }
    }

    private func loadMore() async {
        for source in MusicSource.allCases where model.state(for: source).hasMore {
            await model.loadMore(for: source)
        }
    }

    private func playPlaylist(_ playlist: PlaylistSummary) {
        guard playingPlaylistKey == nil else { return }
        playingPlaylistKey = playlist.key
        Task {
            defer { playingPlaylistKey = nil }
            do {
                let detailModel = OnlinePlaylistDetailViewModel(playlist: playlist, runtime: runtime)
                let tracks = try await detailModel.allTracks()
                guard !tracks.isEmpty else {
                    actionError = "这个歌单还没有可播放的曲目"
                    return
                }
                await playbackService.replaceQueue(tracks)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}

private struct NCMPagingDots: View {
    let count: Int
    let selected: Int

    @Environment(\.m3Scheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(count, 1), id: \.self) { index in
                Capsule()
                    .fill(index == selected ? scheme.primary : scheme.outlineVariant)
                    .frame(width: index == selected ? 10 : 4, height: 4)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

private struct NCMSectionHeader: View {
    let title: String
    let action: String
    let onAction: () -> Void

    @Environment(\.m3Scheme) private var scheme

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: NCMDesignTokens.Typography.sectionTitle, weight: .bold))
                .foregroundStyle(scheme.onSurface)
            Spacer()
            Button(action: onAction) {
                HStack(spacing: 2) {
                    Text(action)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: NCMDesignTokens.Typography.sectionAction, weight: .medium))
                .foregroundStyle(scheme.onSurfaceVariant)
                .frame(minWidth: 52, minHeight: 44, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}

private struct NCMPlaylistCard: View {
    let playlist: PlaylistSummary
    let runtime: SourceRuntime
    let isLoading: Bool
    let onPlay: () -> Void

    @Environment(\.m3Scheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                NavigationLink {
                    OnlinePlaylistDetailView(playlist: playlist, runtime: runtime)
                } label: {
                    RemotePlaylistArtwork(urlString: playlist.img)
                        .frame(width: NCMDesignTokens.Layout.playlistCardWidth, height: NCMDesignTokens.Layout.playlistCardWidth)
                        .clipShape(RoundedRectangle(cornerRadius: NCMDesignTokens.Layout.playlistArtworkCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)

                Text(playlist.playCount.isEmpty ? "播放" : "▶  \(playlist.playCount)")
                    .font(.system(size: NCMDesignTokens.Typography.playCount, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(.black.opacity(0.28), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(5)
                    .allowsHitTesting(false)

                Button(action: onPlay) {
                    Group {
                        if isLoading { ProgressView().tint(.white).controlSize(.small) }
                        else { Image(systemName: "play.fill").font(.system(size: 12, weight: .bold)).offset(x: 1) }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(scheme.primary, in: Circle())
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 1)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .padding(6)
                .accessibilityLabel("播放整个歌单")
            }
            .frame(width: NCMDesignTokens.Layout.playlistCardWidth, height: NCMDesignTokens.Layout.playlistCardWidth)

            NavigationLink {
                OnlinePlaylistDetailView(playlist: playlist, runtime: runtime)
            } label: {
                Text(playlist.name)
                    .font(.system(size: NCMDesignTokens.Typography.playlistCardTitle))
                    .foregroundStyle(scheme.onSurface)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
                    .frame(width: NCMDesignTokens.Layout.playlistCardWidth, alignment: .topLeading)
            }
            .buttonStyle(.plain)
        }
        .frame(width: NCMDesignTokens.Layout.playlistCardWidth, alignment: .top)
        .accessibilityIdentifier("home-playlist-card-\(playlist.key)")
    }
}

private struct NCMPlaylistGridCard: View {
    let playlist: PlaylistSummary
    let runtime: SourceRuntime
    let isLoading: Bool
    let onPlay: () -> Void

    @Environment(\.m3Scheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                NavigationLink {
                    OnlinePlaylistDetailView(playlist: playlist, runtime: runtime)
                } label: {
                    RemotePlaylistArtwork(urlString: playlist.img)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Text(playlist.playCount.isEmpty ? "播放" : "▶  \(playlist.playCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(7)
                    .allowsHitTesting(false)

                Button(action: onPlay) {
                    Group {
                        if isLoading { ProgressView().tint(.white).controlSize(.small) }
                        else { Image(systemName: "play.fill").font(.system(size: 12, weight: .bold)).offset(x: 1) }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(scheme.primary, in: Circle())
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 1)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .padding(6)
                .accessibilityLabel("播放整个歌单")
            }
            .aspectRatio(1, contentMode: .fit)

            NavigationLink {
                OnlinePlaylistDetailView(playlist: playlist, runtime: runtime)
            } label: {
                Text(playlist.name)
                    .font(.system(size: 13))
                    .foregroundStyle(scheme.onSurface)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .buttonStyle(.plain)
        }
        .accessibilityIdentifier("playlist-square-card-\(playlist.key)")
    }
}

private struct NCMHomeSongRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let showDivider: Bool
    let onPlay: () -> Void

    var body: some View {
        SongRow(
            track: track,
            leading: .cover,
            trailing: .play,
            showDivider: showDivider,
            isCurrent: isCurrent,
            isPlaying: isPlaying,
            onPlay: onPlay
        )
    }
}

private struct NCMHomeSongSkeleton: View {
    @Environment(\.m3Scheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6).fill(scheme.surfaceContainerHigh).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(scheme.surfaceContainerHigh).frame(width: 150, height: 11)
                Capsule().fill(scheme.surfaceContainer).frame(width: 110, height: 9)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .accessibilityHidden(true)
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
