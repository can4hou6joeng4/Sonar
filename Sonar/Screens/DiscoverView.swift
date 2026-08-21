import SwiftData
import SwiftUI

struct DiscoverView: View {
    private struct DiscoveryCollection: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let category: String
        let tracks: [Track]
        let playlist: Playlist?
    }

    private static let categories = ["推荐", "歌单", "专辑", "歌手", "最近"]

    let isActive: Bool

    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.capsuleScrollReporter) private var capsuleScrollReporter
    @Query(sort: \TrackRecord.title) private var storedTracks: [TrackRecord]
    @Query(sort: \Playlist.sortIndex) private var playlists: [Playlist]

    @State private var model: SearchViewModel
    @State private var selectedCategory = "推荐"
    @State private var selectedTrackForPlaylist: Track?
    @State private var lastScrollMarkerY: CGFloat?
    @State private var scrollSettleTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    init(runtime: SourceRuntime, isActive: Bool) {
        self.isActive = isActive
        _model = State(initialValue: SearchViewModel(runtime: runtime))
    }

    // 偏离规格：现有 SourceRuntime 没有歌单广场浏览契约；发现页从真实曲库、歌单、
    // 专辑、歌手与最近播放派生内容，避免在界面层复制音源运行时。
    private var collections: [DiscoveryCollection] {
        var result: [DiscoveryCollection] = []

        for playlist in playlists where !playlist.isSystem {
            result.append(DiscoveryCollection(
                id: "playlist-\(playlist.id.uuidString)",
                title: playlist.name,
                subtitle: "我的歌单",
                category: "歌单",
                tracks: playlist.items.sorted { $0.sortIndex < $1.sortIndex }.compactMap(\.track.track),
                playlist: playlist
            ))
        }

        let validTracks = storedTracks.compactMap(\.track)
        let albums = Dictionary(grouping: validTracks.filter { !$0.album.isEmpty }, by: \.album)
        for album in albums.keys.sorted() {
            let values = albums[album] ?? []
            result.append(DiscoveryCollection(
                id: "album-\(album)",
                title: album,
                subtitle: values.first?.artist ?? "专辑精选",
                category: "专辑",
                tracks: values,
                playlist: nil
            ))
        }

        let artists = Dictionary(grouping: validTracks.filter { !$0.artist.isEmpty }, by: \.artist)
        for artist in artists.keys.sorted() {
            result.append(DiscoveryCollection(
                id: "artist-\(artist)",
                title: "\(artist) · 精选",
                subtitle: "\(artist) 的曲目",
                category: "歌手",
                tracks: artists[artist] ?? [],
                playlist: nil
            ))
        }

        if let recent = playlists.first(where: { $0.id == LibraryStore.recentPlaylistID }) {
            result.insert(DiscoveryCollection(
                id: "recent",
                title: "最近播放",
                subtitle: "继续刚才的声音",
                category: "最近",
                tracks: recent.items.sorted { $0.sortIndex < $1.sortIndex }.compactMap(\.track.track),
                playlist: recent
            ), at: 0)
        }
        return result
    }

    private var visibleCollections: [DiscoveryCollection] {
        selectedCategory == "推荐" ? collections : collections.filter { $0.category == selectedCategory }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("发现")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(scheme.onSurface)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 10)

            ScrollView {
                LazyVStack(spacing: 0) {
                    scrollMarker
                    searchField
                    if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        discoveryContent
                    } else {
                        searchContent
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollIndicators(.hidden)
            .coordinateSpace(name: CapsuleScrollTracking.coordinateSpace)
            .onPreferenceChange(CapsuleScrollOffsetPreferenceKey.self, perform: reportScrollOffset)
            .onDisappear(perform: finishScrollTracking)
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .sheet(item: $selectedTrackForPlaylist) { track in
            AddToPlaylistSheet(track: track)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: isActive) { _, _ in finishScrollTracking() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var scrollMarker: some View {
        Color.clear
            .frame(height: 0)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CapsuleScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named(CapsuleScrollTracking.coordinateSpace)).minY
                    )
                }
            }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
            TextField("搜索曲目、歌手或专辑", text: $model.query)
                .font(.system(size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    searchFocused = false
                    Task { await model.search() }
                }
                .accessibilityIdentifier("discover-search-field")
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    model.queryChanged()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空")
            }
        }
        .foregroundStyle(scheme.onSurfaceVariant)
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(scheme.appInputFill, in: Capsule())
        .overlay {
            Capsule()
                .stroke(searchFocused ? scheme.primary : scheme.outlineVariant, lineWidth: searchFocused ? 1.6 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 10)
        .onChange(of: model.query) { _, _ in model.queryChanged() }
    }

    private var discoveryContent: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.categories, id: \.self) { category in
                        Button {
                            searchFocused = false
                            selectedCategory = category
                        } label: {
                            HStack(spacing: 6) {
                                if selectedCategory == category {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                Text(category)
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(
                                selectedCategory == category
                                    ? scheme.onSecondaryContainer
                                    : scheme.onSurfaceVariant
                            )
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .background(
                                selectedCategory == category ? scheme.secondaryContainer : .clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay {
                                if selectedCategory != category {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(scheme.outlineVariant, lineWidth: 1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("discover-category-\(category)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 12)
            }

            if visibleCollections.isEmpty {
                ContentUnavailableView(
                    "还没有可发现的歌单",
                    systemImage: "music.note.list",
                    description: Text("搜索并播放歌曲后，这里会按歌单、专辑和歌手整理。")
                )
                .padding(.top, 52)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())],
                    spacing: 16
                ) {
                    ForEach(visibleCollections) { collection in
                        NavigationLink {
                            destination(for: collection)
                        } label: {
                            discoveryCard(collection)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("discover-collection-\(collection.id)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if !model.suggestions.isEmpty && !model.hasSearched {
            VStack(spacing: 0) {
                sectionTitle("搜索建议")
                ForEach(model.suggestions, id: \.self) { suggestion in
                    Button {
                        searchFocused = false
                        model.query = suggestion
                        Task { await model.search() }
                    } label: {
                        Label(suggestion, systemImage: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(scheme.onSurface)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .padding(.horizontal, 18)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if model.isLoading {
            ProgressView("正在搜索…")
                .frame(maxWidth: .infinity)
                .padding(.top, 72)
        } else if let errorMessage = model.errorMessage {
            ContentUnavailableView(
                "搜索不可用",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .padding(.top, 52)
        } else if model.hasSearched, model.results.isEmpty {
            ContentUnavailableView("未找到结果", systemImage: "music.note.list")
                .padding(.top, 52)
        } else if !model.results.isEmpty {
            sectionTitle("单曲 · \(model.results.count)")
            ForEach(Array(model.results.enumerated()), id: \.element.musicID) { index, track in
                SongRow(
                    track: track,
                    isCurrent: playbackService.queue.current?.musicID == track.musicID,
                    isPlaying: playbackService.state == .playing,
                    onPlay: {
                        searchFocused = false
                        Task { await playbackService.replaceQueue(model.results, startingAt: index) }
                    },
                    onAction: {
                        searchFocused = false
                        selectedTrackForPlaylist = track
                    }
                )
                .padding(.horizontal, 14)
            }
        } else {
            ContentUnavailableView("输入关键词后搜索", systemImage: "magnifyingglass")
                .padding(.top, 52)
        }
    }

    private func discoveryCard(_ collection: DiscoveryCollection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    PlayerArtwork(track: collection.tracks.first, size: proxy.size.width)
                        .frame(width: proxy.size.width, height: proxy.size.width)
                    Text("\(collection.tracks.count) 首")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 22)
                        .background(.black.opacity(0.42), in: Capsule())
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .aspectRatio(1, contentMode: .fit)
            Text(collection.title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(scheme.onSurface)
                .lineLimit(2)
                .frame(minHeight: 34, alignment: .topLeading)
            Text(collection.subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(scheme.onSurfaceVariant)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func destination(for collection: DiscoveryCollection) -> some View {
        if let playlist = collection.playlist {
            PlaylistDetailView(playlist: playlist)
        } else {
            PlaylistDetailView(
                title: collection.title,
                subtitle: collection.subtitle,
                description: "来自曲库的\(collection.category)精选。",
                tracks: collection.tracks
            )
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(scheme.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 8)
    }

    private func reportScrollOffset(_ markerY: CGFloat) {
        guard isActive else {
            lastScrollMarkerY = nil
            return
        }
        if let lastScrollMarkerY { capsuleScrollReporter.update(lastScrollMarkerY - markerY) }
        self.lastScrollMarkerY = markerY
        scrollSettleTask?.cancel()
        scrollSettleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            capsuleScrollReporter.settle()
        }
    }

    private func finishScrollTracking() {
        scrollSettleTask?.cancel()
        scrollSettleTask = nil
        lastScrollMarkerY = nil
        if isActive { capsuleScrollReporter.settle() }
    }
}

extension Track: Identifiable {
    public var id: String { musicID }
}
