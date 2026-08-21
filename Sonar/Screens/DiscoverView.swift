import SwiftUI

private struct DiscoveryPagerOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: [MusicSource: CGFloat] = [:]

    static func reduce(value: inout [MusicSource: CGFloat], nextValue: () -> [MusicSource: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct DiscoveryScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: [MusicSource: CGFloat] = [:]

    static func reduce(value: inout [MusicSource: CGFloat], nextValue: () -> [MusicSource: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct DiscoveryLoadMoreOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: [MusicSource: CGFloat] = [:]

    static func reduce(value: inout [MusicSource: CGFloat], nextValue: () -> [MusicSource: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct DiscoverView: View {
    let isActive: Bool
    private let runtime: SourceRuntime

    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @Environment(\.capsuleScrollReporter) private var capsuleScrollReporter

    @State private var discoveryModel: DiscoveryViewModel
    @State private var searchModel: SearchViewModel
    @State private var selectedSource: MusicSource = .wy
    @State private var scrollTarget: MusicSource? = .wy
    @State private var pagerProgress: CGFloat = 0
    @State private var previewPlaylist: PlaylistSummary?
    @State private var isCategoryFabExpanded = false
    @State private var selectedTrackForPlaylist: Track?
    @State private var lastScrollMarkerY: CGFloat?
    @State private var scrollSettleTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    init(runtime: SourceRuntime, isActive: Bool) {
        self.isActive = isActive
        self.runtime = runtime
        _discoveryModel = State(initialValue: DiscoveryViewModel(runtime: runtime))
        _searchModel = State(initialValue: SearchViewModel(runtime: runtime))
    }

    private var isSearching: Bool {
        !searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("发现")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(scheme.onSurface)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 10)

            searchField

            if isSearching {
                searchResults
            } else {
                DiscoverySourceSelector(
                    selectedSource: selectedSource,
                    progress: pagerProgress,
                    onSelect: selectSource
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

                discoveryPager
            }
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .overlay {
            if !isSearching, selectedSource.playlistCategories.count > 1 {
                DiscoveryCategoryFabLayer(
                    source: selectedSource,
                    selectedCategory: discoveryModel.selectedCategory(for: selectedSource),
                    isExpanded: $isCategoryFabExpanded,
                    onSelect: { category in
                        Task { await discoveryModel.selectCategory(category, for: selectedSource) }
                    }
                )
            }
        }
        .sheet(item: $previewPlaylist) { playlist in
            PlaylistPreviewSheet(playlist: playlist)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedTrackForPlaylist) { track in
            AddToPlaylistSheet(track: track)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: isActive) { _, _ in finishScrollTracking() }
        .onChange(of: selectedSource) { _, _ in isCategoryFabExpanded = false }
        .onChange(of: isSearching) { _, _ in isCategoryFabExpanded = false }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
            TextField("搜索曲目、歌手或专辑", text: $searchModel.query)
                .font(.system(size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    searchFocused = false
                    Task { await searchModel.search() }
                }
                .accessibilityIdentifier("discover-search-field")
            if !searchModel.query.isEmpty {
                Button {
                    searchModel.query = ""
                    searchModel.queryChanged()
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
        .onChange(of: searchModel.query) { _, _ in searchModel.queryChanged() }
    }

    private var discoveryPager: some View {
        GeometryReader { proxy in
            let pageWidth = max(proxy.size.width, 1)
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(MusicSource.allCases, id: \.self) { source in
                        DiscoverySourcePage(
                            source: source,
                            pageWidth: pageWidth,
                            viewportHeight: proxy.size.height,
                            model: discoveryModel,
                            runtime: runtime,
                            onPreview: { previewPlaylist = $0 }
                        )
                        .frame(width: pageWidth)
                        .id(source)
                        .background {
                            GeometryReader { pageProxy in
                                Color.clear.preference(
                                    key: DiscoveryPagerOffsetPreferenceKey.self,
                                    value: [source: pageProxy.frame(in: .named("discovery-pager")).minX]
                                )
                            }
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .coordinateSpace(name: "discovery-pager")
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollTarget)
            .onPreferenceChange(DiscoveryPagerOffsetPreferenceKey.self) { offsets in
                guard let firstOffset = offsets[.wy] else { return }
                pagerProgress = min(max(-firstOffset / pageWidth, 0), 1)
            }
            .onPreferenceChange(DiscoveryScrollOffsetPreferenceKey.self) { offsets in
                guard let marker = offsets[selectedSource] else { return }
                reportScrollOffset(marker)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                selectedSource = target
            }
        }
    }

    private var searchResults: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !searchModel.suggestions.isEmpty && !searchModel.hasSearched {
                    sectionTitle("搜索建议")
                    ForEach(searchModel.suggestions, id: \.self) { suggestion in
                        Button {
                            searchFocused = false
                            searchModel.query = suggestion
                            Task { await searchModel.search() }
                        } label: {
                            Label(suggestion, systemImage: "magnifyingglass")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(scheme.onSurface)
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                .padding(.horizontal, 18)
                        }
                        .buttonStyle(.plain)
                    }
                } else if searchModel.isLoading {
                    ProgressView("正在搜索…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 72)
                } else if let errorMessage = searchModel.errorMessage {
                    ContentUnavailableView("搜索不可用", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                        .padding(.top, 52)
                } else if searchModel.hasSearched, searchModel.results.isEmpty {
                    ContentUnavailableView("未找到结果", systemImage: "music.note.list")
                        .padding(.top, 52)
                } else if !searchModel.results.isEmpty {
                    sectionTitle("单曲 · \(searchModel.results.count)")
                    ForEach(Array(searchModel.results.enumerated()), id: \.element.musicID) { index, track in
                        SongRow(
                            track: track,
                            isCurrent: playbackService.queue.current?.musicID == track.musicID,
                            isPlaying: playbackService.state == .playing,
                            onPlay: {
                                Task { await playbackService.replaceQueue(searchModel.results, startingAt: index) }
                            },
                            onAction: { selectedTrackForPlaylist = track }
                        )
                        .padding(.horizontal, 14)
                    }
                } else {
                    ContentUnavailableView("输入关键词后搜索", systemImage: "magnifyingglass")
                        .padding(.top, 52)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.hidden)
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

    private func selectSource(_ source: MusicSource) {
        searchFocused = false
        selectedSource = source
        if reduceMotion {
            scrollTarget = source
        } else {
            withAnimation(AppMotion.emphasized(duration: AppMotion.medium, reduceMotion: false)) {
                scrollTarget = source
            }
        }
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

private struct DiscoverySourceSelector: View {
    @Environment(\.m3Scheme) private var scheme

    let selectedSource: MusicSource
    let progress: CGFloat
    let onSelect: (MusicSource) -> Void

    var body: some View {
        GeometryReader { proxy in
            let innerWidth = max(proxy.size.width - 4, 0)
            let segmentWidth = innerWidth / CGFloat(MusicSource.allCases.count)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(scheme.secondaryContainer)
                    .frame(width: segmentWidth, height: 34)
                    .offset(x: 2 + segmentWidth * progress)

                HStack(spacing: 0) {
                    ForEach(MusicSource.allCases, id: \.self) { source in
                        Button {
                            onSelect(source)
                        } label: {
                            Text(source.displayName)
                                .font(.system(size: 11.5, weight: selectedSource == source ? .semibold : .medium))
                                .foregroundStyle(selectedSource == source ? scheme.onSecondaryContainer : scheme.onSurfaceVariant)
                                .tracking(0)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("discovery-source-\(source.rawValue)")
                    }
                }
                .padding(2)
            }
        }
        .frame(height: 38)
        .background(scheme.surfaceContainer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(scheme.outlineVariant.opacity(0.22), lineWidth: 1)

                Color.clear
                    .accessibilityElement()
                    .accessibilityLabel("音源筛选")
                    .accessibilityIdentifier("discovery-source-filter")
                    .accessibilityRespondsToUserInteraction(false)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct DiscoverySourcePage: View {
    @Environment(\.m3Scheme) private var scheme

    @State private var lastAutomaticLoadToken: String?

    let source: MusicSource
    let pageWidth: CGFloat
    let viewportHeight: CGFloat
    let model: DiscoveryViewModel
    let runtime: SourceRuntime
    let onPreview: (PlaylistSummary) -> Void

    var body: some View {
        let state = model.state(for: source)
        ScrollView {
            Color.clear
                .frame(height: 0)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: DiscoveryScrollOffsetPreferenceKey.self,
                            value: [source: proxy.frame(in: .named("discovery-scroll-\(source.rawValue)")).minY]
                        )
                    }
                }

            if state.isLoading, state.items.isEmpty {
                ProgressView("正在加载歌单…")
                    .frame(maxWidth: .infinity, minHeight: viewportHeight)
            } else if let error = state.errorMessage, state.items.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await model.loadInitial(for: source) } }
                }
                .frame(minHeight: viewportHeight)
            } else if state.items.isEmpty {
                ContentUnavailableView {
                    Label("暂无在线歌单", systemImage: "music.note.list")
                } actions: {
                    Button("刷新") { Task { await model.refresh(source) } }
                }
                .frame(minHeight: viewportHeight)
            } else {
                MasonryPlaylistGrid(items: state.items, availableWidth: pageWidth, runtime: runtime, onPreview: onPreview)

                if state.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                } else if state.loadMoreError != nil {
                    Button {
                        Task { await model.loadMore(for: source) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                    .accessibilityLabel("重试加载更多")
                }

                Color.clear
                    .frame(height: 1)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: DiscoveryLoadMoreOffsetPreferenceKey.self,
                                value: [source: proxy.frame(in: .named("discovery-scroll-\(source.rawValue)")).minY]
                            )
                        }
                    }
                Color.clear.frame(height: 156)
            }
        }
        .coordinateSpace(name: "discovery-scroll-\(source.rawValue)")
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh(source) }
        .onPreferenceChange(DiscoveryLoadMoreOffsetPreferenceKey.self) { offsets in
            guard let triggerY = offsets[source], triggerY - viewportHeight <= 600 else { return }
            let token = "\(model.selectedCategory(for: source).id):\(state.page)"
            Task { @MainActor in
                await Task.yield()
                guard lastAutomaticLoadToken != token else { return }
                lastAutomaticLoadToken = token
                await model.loadMore(for: source)
            }
        }
        .background(scheme.appSurface)
        .task { await model.loadInitial(for: source) }
    }
}

private struct MasonryPlaylistGrid: View {
    let items: [PlaylistSummary]
    let availableWidth: CGFloat
    let runtime: SourceRuntime
    let onPreview: (PlaylistSummary) -> Void

    private let gap: CGFloat = 10

    var body: some View {
        let contentWidth = min(max(availableWidth - 24, 0), 960)
        let columnWidth = max((contentWidth - gap) / 2, 1)
        let assignments = DiscoveryMasonry.columnAssignments(
            for: items.map(\.key),
            columnWidth: columnWidth,
            gap: gap
        )

        HStack(alignment: .top, spacing: gap) {
            ForEach(0..<2, id: \.self) { column in
                LazyVStack(spacing: gap) {
                    ForEach(Array(items.enumerated()).filter { assignments[$0.offset] == column }, id: \.element.key) { _, item in
                        NavigationLink {
                            OnlinePlaylistDetailView(playlist: item, runtime: runtime)
                        } label: {
                            PlaylistDiscoveryCard(item: item, width: columnWidth)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(LongPressGesture().onEnded { _ in onPreview(item) })
                        .accessibilityIdentifier("discovery-card-\(item.key)")
                    }
                }
                .frame(width: columnWidth)
            }
        }
        .frame(width: contentWidth, alignment: .top)
        .padding(.top, 2)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }
}

private struct DiscoveryCategoryFabLayer: View {
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.sonarReduceMotion) private var reduceMotion

    let source: MusicSource
    let selectedCategory: PlaylistCategory
    @Binding var isExpanded: Bool
    let onSelect: (PlaylistCategory) -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { setExpanded(false) }
                    .ignoresSafeArea()
            }

            VStack(alignment: .trailing, spacing: 10) {
                if isExpanded {
                    ForEach(source.playlistCategories) { category in
                        Button {
                            onSelect(category)
                            setExpanded(false)
                        } label: {
                            Label {
                                Text(category.name)
                            } icon: {
                                Image(systemName: category == selectedCategory ? "checkmark" : icon(for: category))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(category == selectedCategory ? scheme.secondary : scheme.surfaceContainerHigh)
                        .foregroundStyle(category == selectedCategory ? scheme.onSecondaryContainer : scheme.onSurface)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .accessibilityIdentifier("discovery-category-\(source.rawValue)-\(category.id)")
                    }
                }

                Button {
                    setExpanded(!isExpanded)
                } label: {
                    Label(
                        isExpanded ? "关闭" : selectedCategory.name,
                        systemImage: isExpanded ? "xmark" : "line.3.horizontal.decrease"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(scheme.primary)
                .foregroundStyle(scheme.onPrimary)
                .accessibilityIdentifier("discovery-category-fab")
            }
            .padding(.trailing, 18)
            .padding(.bottom, 82)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        let animation = expanded
            ? AppMotion.emphasizedDecelerate(duration: AppMotion.medium, reduceMotion: reduceMotion)
            : AppMotion.emphasizedAccelerate(duration: AppMotion.medium, reduceMotion: reduceMotion)
        withAnimation(animation) { isExpanded = expanded }
    }

    private func icon(for category: PlaylistCategory) -> String {
        switch category.id {
        case "hot", "5": "flame.fill"
        case "2": "sparkles"
        default: "line.3.horizontal.decrease"
        }
    }
}

private struct PlaylistDiscoveryCard: View {
    @Environment(\.m3Scheme) private var scheme

    let item: PlaylistSummary
    let width: CGFloat

    var body: some View {
        let ratio = DiscoveryMasonry.ratio(for: item.key)
        VStack(alignment: .leading, spacing: 0) {
            RemotePlaylistArtwork(urlString: item.img)
                .frame(width: width, height: width / ratio)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(scheme.onSurface)
                    .tracking(0)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .topLeading)
                Text(item.author.isEmpty ? item.source.displayName : item.author)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(scheme.onSurfaceVariant)
                    .tracking(0)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.init(top: 9, leading: 10, bottom: 10, trailing: 10))
            .frame(height: 82, alignment: .top)
        }
        .frame(width: width)
        .background(scheme.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(scheme.outlineVariant.opacity(0.24), lineWidth: 1)
        }
        .contentShape(Rectangle())
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
            case let .success(image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder(systemImage: "exclamationmark.triangle")
            case .empty:
                placeholder(systemImage: "music.note")
            @unknown default:
                placeholder(systemImage: "music.note")
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

private struct PlaylistPreviewSheet: View {
    @Environment(\.m3Scheme) private var scheme

    let playlist: PlaylistSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                RemotePlaylistArtwork(urlString: playlist.img)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(playlist.name)
                        .font(.headline)
                        .foregroundStyle(scheme.onSurface)
                        .lineLimit(3)
                    Text("\(playlist.source.displayName) · \(playlist.author)")
                        .font(.subheadline)
                        .foregroundStyle(scheme.onSurfaceVariant)
                        .lineLimit(2)
                }
            }
            if let description = playlist.desc, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(scheme.onSurfaceVariant)
                    .lineLimit(5)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(scheme.surface)
    }
}

extension PlaylistSummary {
    var key: String { "\(source.rawValue):\(id)" }
}

extension Track: Identifiable {
    public var id: String { musicID }
}
