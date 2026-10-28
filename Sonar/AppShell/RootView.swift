import SwiftData
import SwiftUI
import UIKit

private enum HomeTab {
    case home, library
}

private enum ShellLayer: Hashable {
    case route
    case player
}

private enum HomeSearchDestination: Hashable {
    case artist(ArtistSummary)
    case album(AlbumSummary)
    case playlist(PlaylistSummary)

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .artist(artist):
            hasher.combine("artist")
            hasher.combine(artist.stableID)
        case let .album(album):
            hasher.combine("album")
            hasher.combine(album.stableID)
        case let .playlist(playlist):
            hasher.combine("playlist")
            hasher.combine(playlist.key)
        }
    }
}

enum SettingsDrawerMetrics {
    static let activationWidth: CGFloat = 26
    static let widthRatio: CGFloat = 0.84
    static let minimumWidth: CGFloat = 280
    static let maximumWidth: CGFloat = 340
    static let completionRatio: CGFloat = 0.35
    static let predictedCompletionRatio: CGFloat = 0.55

    static func width(for containerWidth: CGFloat) -> CGFloat {
        let availableWidth = max(containerWidth, 0)
        let preferredWidth = min(max(availableWidth * widthRatio, minimumWidth), maximumWidth)
        return min(preferredWidth, availableWidth)
    }

    static func canStart(at x: CGFloat) -> Bool {
        x >= 0 && x < activationWidth
    }

    static func progress(translation: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(max(translation / width, 0), 1)
    }

    static func shouldOpen(translation: CGFloat, predictedEnd: CGFloat, width: CGFloat) -> Bool {
        translation > width * completionRatio
            || predictedEnd > width * predictedCompletionRatio
    }

    static func shouldClose(translation: CGFloat, predictedEnd: CGFloat, width: CGFloat) -> Bool {
        translation < -width * completionRatio
            || predictedEnd < -width * predictedCompletionRatio
    }
}

private struct RootSettingsDrawerGestureModifier: ViewModifier {
    let isEnabled: Bool
    let onOpen: () -> Void
    let onChanged: (DragGesture.Value) -> Void
    let onEnded: (DragGesture.Value) -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .onChanged(onChanged)
                    .onEnded(onEnded),
                including: isEnabled ? .all : .none
            )
            .accessibilityAction(named: Text("打开设置")) {
                if isEnabled { onOpen() }
            }
    }
}

extension View {
    func rootSettingsDrawerGesture(
        isEnabled: Bool,
        onOpen: @escaping () -> Void,
        onChanged: @escaping (DragGesture.Value) -> Void,
        onEnded: @escaping (DragGesture.Value) -> Void
    ) -> some View {
        modifier(
            RootSettingsDrawerGestureModifier(
                isEnabled: isEnabled,
                onOpen: onOpen,
                onChanged: onChanged,
                onEnded: onEnded
            )
        )
    }
}

private struct ShellSafeAreaInsetsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

private struct SourceRuntimeEnvironmentKey: EnvironmentKey {
    static let defaultValue: SourceRuntime? = nil
}

private struct TrackDetailRefreshCoordinatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: TrackDetailRefreshCoordinator? = nil
}

private struct LyricsServiceEnvironmentKey: EnvironmentKey {
    static let defaultValue: LyricsService? = nil
}

extension EnvironmentValues {
    var shellSafeAreaInsets: EdgeInsets {
        get { self[ShellSafeAreaInsetsKey.self] }
        set { self[ShellSafeAreaInsetsKey.self] = newValue }
    }

    public var sourceRuntime: SourceRuntime? {
        get { self[SourceRuntimeEnvironmentKey.self] }
        set { self[SourceRuntimeEnvironmentKey.self] = newValue }
    }

    public var trackDetailRefreshCoordinator: TrackDetailRefreshCoordinator? {
        get { self[TrackDetailRefreshCoordinatorEnvironmentKey.self] }
        set { self[TrackDetailRefreshCoordinatorEnvironmentKey.self] = newValue }
    }

    public var lyricsService: LyricsService? {
        get { self[LyricsServiceEnvironmentKey.self] }
        set { self[LyricsServiceEnvironmentKey.self] = newValue }
    }
}

enum ShellBottomLayout {
    static func contentReservation(hasCurrentTrack: Bool = true, safeAreaBottom: CGFloat) -> CGFloat {
        SpotlightLayout.bottomReservation(hasTrack: hasCurrentTrack)
    }

    static func miniPlayerVerticalOffset(safeAreaBottom: CGFloat) -> CGFloat {
        max(safeAreaBottom, 0)
            + MiniPlayerDockPresentation.safeAreaCompaction(safeAreaBottom: safeAreaBottom)
    }
}

struct RootView: View {
    let sourceRuntime: SourceRuntime

    @Environment(PlaybackService.self) private var playbackService
    @Environment(ConfirmationCenter.self) private var confirmationCenter
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(SonarThemeState.self) private var themeState
    @Environment(\.artworkService) private var artworkService
    @Environment(\.trackDetailRefreshCoordinator) private var trackDetailRefreshCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.sonarReduceMotion) private var reduceMotion

    @State private var pullController = PlayerPullController()
    @State private var playerSurface: PlayerSurface = .artwork
    @State private var homeTab: HomeTab = .home
    @State private var routeRevision = 0
    @State private var introIsVisible = true
    @State private var drawerIsOpen = false
    @State private var drawerDragTranslation: CGFloat = 0
    @State private var edgeDrawerDragIsActive = false
    @State private var artworkRequests = ArtworkRequestGate()
    @State private var searchModel: SearchViewModel
    @State private var searchIsPresented = false
    @State private var searchDestination: HomeSearchDestination?
    @State private var focusSearchOnAppear = false

    init(sourceRuntime: SourceRuntime) {
        self.sourceRuntime = sourceRuntime
        _searchModel = State(initialValue: SearchViewModel(runtime: sourceRuntime))
    }

    private var searchOverlayIsVisible: Bool {
        searchIsPresented && searchDestination == nil
    }

    private var hasCurrentTrack: Bool {
        playbackService.queue.current != nil
    }

    private var successfullyLoadedTrackID: String? {
        switch playbackService.state {
        case .playing, .paused:
            playbackService.queue.current?.musicID
        case .idle, .loading, .failed:
            nil
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let drawerWidth = SettingsDrawerMetrics.width(for: proxy.size.width)
            let drawerProgress = settingsDrawerProgress(width: drawerWidth)
            let playerTravel = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom

            ZStack(alignment: .bottom) {
                routeContent(
                    drawerWidth: drawerWidth,
                    safeAreaBottom: proxy.safeAreaInsets.bottom
                )
                    .id(ShellLayer.route)
                    .accessibilityHidden(introIsVisible || pullController.pull > 0 || drawerProgress > 0 || searchOverlayIsVisible)
                    .environment(\.shellSafeAreaInsets, proxy.safeAreaInsets)
                    .allowsHitTesting(!introIsVisible && drawerProgress == 0 && pullController.pull == 0 && !searchOverlayIsVisible)

                if pullController.playerMounted {
                    FlowingLightBackground(track: playbackService.queue.current)
                        .scaleEffect(pullController.scale)
                        .opacity(pullController.opacity)
                        .ignoresSafeArea()
                        .offset(y: CGFloat(1 - pullController.pull) * playerTravel + pullController.translationY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(NCMDesignTokens.Layer.player - 1)
                }

                ZStack {
                    if pullController.playerMounted {
                        PlayerPage(
                            pullController: pullController,
                            viewportHeight: proxy.size.height,
                            selectedSurface: $playerSurface,
                            onClose: { pullController.close(reduceMotion: reduceMotion) }
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(pullController.scale)
                        .opacity(pullController.opacity)
                        .offset(y: CGFloat(1 - pullController.pull) * playerTravel + pullController.translationY)
                        .id(ShellLayer.player)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                // The player stays mounted after closing; clip this layer without clipping bottom chrome.
                .clipped()
                .allowsHitTesting(pullController.pull > 0)
                .accessibilityHidden(pullController.pull == 0)
                .zIndex(NCMDesignTokens.Layer.player)

                VStack(spacing: SpotlightLayout.chromeSpacing) {
                    if hasCurrentTrack {
                        NCMMiniPlayer(
                            safeAreaBottom: 0,
                            onOpenPlayer: {
                                closeSearch()
                                closeSettingsDrawer()
                                playerSurface = .artwork
                                pullController.open(reduceMotion: reduceMotion)
                            },
                            onOpenQueue: {
                                closeSearch()
                                closeSettingsDrawer()
                                playerSurface = .queue
                                pullController.open(reduceMotion: reduceMotion)
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    bottomNavigation
                }
                .padding(.horizontal, 18)
                .padding(.bottom, SpotlightLayout.bottomPadding)
                .background(alignment: .bottom) {
                    LinearGradient(colors: [scheme.appSurface.opacity(0), scheme.appSurface, scheme.appSurface], startPoint: .top, endPoint: .bottom)
                        .padding(.top, -20)
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                }
                .opacity(pullController.toolbarReveal)
                .animation(AppMotion.emphasized(duration: AppMotion.medium, reduceMotion: reduceMotion), value: hasCurrentTrack)
                .allowsHitTesting(!introIsVisible && pullController.pull == 0 && drawerProgress == 0 && !searchOverlayIsVisible)
                .accessibilityHidden(introIsVisible || pullController.pull > 0 || drawerProgress > 0 || searchOverlayIsVisible)
                .zIndex(NCMDesignTokens.Layer.miniPlayer)

                settingsDrawer(width: drawerWidth, progress: drawerProgress)
                    .zIndex(25)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background {
            scheme.appSurface.ignoresSafeArea()
        }
        .preferredColorScheme(introIsVisible || pullController.pull > 0 ? .dark : themeState.appearanceMode.colorScheme)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay {
            if searchOverlayIsVisible {
                HomeSearchOverlay(
                    model: searchModel,
                    focusOnAppear: focusSearchOnAppear,
                    onClose: closeSearch,
                    onOpenArtist: {
                        focusSearchOnAppear = false
                        searchDestination = .artist($0)
                    },
                    onOpenAlbum: {
                        focusSearchOnAppear = false
                        searchDestination = .album($0)
                    },
                    onOpenPlaylist: {
                        focusSearchOnAppear = false
                        searchDestination = .playlist($0)
                    }
                )
                .transition(.opacity)
            }
        }
        .overlay {
            if introIsVisible {
                SonarWelcomeView { introIsVisible = false }
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
            }
        }
        .task {
            PerfLog.mark("first_frame")
            KeyboardDiagnostics.shared.start()
            await playbackService.restoreLastSessionIfNeeded()
            await warmUpCaches()
        }
        .task(id: playbackService.queue.current?.musicID, updateArtworkAndTheme)
        .onChange(of: pullController.pull) { _, pull in
            if pull > 0 {
                closeSearch()
                closeSettingsDrawer()
            }
        }
        .overlay(alignment: .bottom) {
            ToastOverlay()
                .padding(.bottom, 96)
                .zIndex(NCMDesignTokens.Layer.toast)
        }
        .alert(item: confirmationBinding) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                dismissButton: .default(Text(confirmation.acknowledgment)) {
                    confirmationCenter.acknowledge()
                }
            )
        }
        .task {
            let store = LibraryStore(context: modelContext)
            if let playlist = try? store.ensurePersonalPlaylist() {
                WidgetShareStore.shared.updateFavoritesCount(playlist.items.count)
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
    }

    private func routeContent(drawerWidth: CGFloat, safeAreaBottom: CGFloat) -> some View {
        NavigationStack {
            Group {
                switch homeTab {
                case .home:
                    DiscoverView(
                        isActive: !searchOverlayIsVisible,
                        showsSpotlight: true,
                        onOpenSearch: openSearch,
                        onOpenSettings: openSettingsDrawer,
                        onShowCollection: { selectTab(.library) },
                        onSettingsDragChanged: { handleEdgeDrawerDragChanged($0, width: drawerWidth) },
                        onSettingsDragEnded: { handleEdgeDrawerDragEnded($0, width: drawerWidth) }
                    )
                case .library:
                    LibraryPlaylistView(onOpenSettings: openSettingsDrawer)
                }
            }
            .navigationDestination(item: $searchDestination) { destination in
                switch destination {
                case let .artist(artist):
                    ArtistDetailView(artist: artist, runtime: sourceRuntime)
                case let .album(album):
                    AlbumDetailView(album: album, runtime: sourceRuntime)
                case let .playlist(playlist):
                    RemotePlaylistDetailView(playlist: playlist, runtime: sourceRuntime)
                }
            }
        }
        .id(routeRevision)
        .transition(.opacity)
        .environment(\.bottomChromeHeight, BottomChromeLayout.height(hasCurrentTrack: hasCurrentTrack))
    }

    private var bottomNavigation: some View {
        HStack(spacing: 0) {
            navigationButton("music.note", title: "首页", identifier: "tab-home", selected: homeTab == .home) { selectTab(.home) }
            navigationButton("rectangle.stack", title: "资料库", identifier: "tab-library", selected: homeTab == .library) { selectTab(.library) }
        }
        .frame(height: SpotlightLayout.navigationHeight)
    }

    private func selectTab(_ tab: HomeTab) {
        closeSearch()
        searchDestination = nil
        withAnimation(AppMotion.emphasized(duration: 0.22, reduceMotion: reduceMotion)) {
            homeTab = tab
            // Reset pushed pages while leaving the root playback service and player mounted.
            routeRevision += 1
        }
    }

    private func navigationButton(_ symbol: String, title: String, identifier: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.light()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? scheme.onSurface : scheme.onSurfaceVariant.opacity(0.75))
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.circleIcon(diameter: 42, haptic: false))
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func openSearch() {
        closeSettingsDrawer()
        focusSearchOnAppear = true
        withAnimation(AppMotion.emphasized(duration: AppMotion.short, reduceMotion: reduceMotion)) {
            searchIsPresented = true
        }
    }

    private func closeSearch() {
        guard searchIsPresented else { return }
        searchModel.cancelLiveSearch()
        searchModel.query = ""
        searchModel.queryChanged()
        focusSearchOnAppear = false
        withAnimation(AppMotion.emphasized(duration: AppMotion.short, reduceMotion: reduceMotion)) {
            searchIsPresented = false
        }
    }

    private var confirmationBinding: Binding<AppConfirmation?> {
        Binding(
            get: { confirmationCenter.confirmation },
            set: { value in
                if value == nil { confirmationCenter.acknowledge() }
            }
        )
    }

    private func settingsDrawerProgress(width: CGFloat) -> CGFloat {
        let visibleWidth = (drawerIsOpen ? width : 0) + drawerDragTranslation
        return SettingsDrawerMetrics.progress(translation: visibleWidth, width: width)
    }

    private func openSettingsDrawer() {
        guard pullController.pull == 0, !searchOverlayIsVisible else { return }
        edgeDrawerDragIsActive = false
        animateDrawerChange {
            drawerIsOpen = true
            drawerDragTranslation = 0
        }
    }

    private func closeSettingsDrawer() {
        edgeDrawerDragIsActive = false
        animateDrawerChange {
            drawerIsOpen = false
            drawerDragTranslation = 0
        }
    }

    private func handleEdgeDrawerDragChanged(_ value: DragGesture.Value, width: CGFloat) {
        guard pullController.pull == 0, !drawerIsOpen else { return }
        guard edgeDrawerDragIsActive || SettingsDrawerMetrics.canStart(at: value.startLocation.x) else { return }
        guard edgeDrawerDragIsActive
            || (value.translation.width > 0 && abs(value.translation.width) > abs(value.translation.height))
        else { return }

        edgeDrawerDragIsActive = true
        drawerDragTranslation = min(max(value.translation.width, 0), width)
    }

    private func handleEdgeDrawerDragEnded(_ value: DragGesture.Value, width: CGFloat) {
        guard edgeDrawerDragIsActive else { return }
        let shouldOpen = SettingsDrawerMetrics.shouldOpen(
            translation: max(value.translation.width, drawerDragTranslation),
            predictedEnd: value.predictedEndTranslation.width,
            width: width
        )
        edgeDrawerDragIsActive = false
        animateDrawerChange {
            drawerIsOpen = shouldOpen
            drawerDragTranslation = 0
        }
    }

    private func handleOpenDrawerDragChanged(_ value: DragGesture.Value, width: CGFloat) {
        guard drawerIsOpen else { return }
        drawerDragTranslation = min(max(value.translation.width, -width), 0)
    }

    private func handleOpenDrawerDragEnded(_ value: DragGesture.Value, width: CGFloat) {
        guard drawerIsOpen else { return }
        let shouldClose = SettingsDrawerMetrics.shouldClose(
            translation: min(value.translation.width, drawerDragTranslation),
            predictedEnd: value.predictedEndTranslation.width,
            width: width
        )
        animateDrawerChange {
            drawerIsOpen = !shouldClose
            drawerDragTranslation = 0
        }
    }

    private func animateDrawerChange(_ updates: @escaping () -> Void) {
        withAnimation(AppMotion.emphasized(duration: AppMotion.medium, reduceMotion: reduceMotion)) {
            updates()
        }
    }

    private func settingsDrawer(width: CGFloat, progress: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.42 * progress)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: closeSettingsDrawer)
                .accessibilityHidden(true)

            SettingsView(onClose: closeSettingsDrawer)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .offset(x: -width + width * progress)
                .shadow(color: .black.opacity(0.22 * progress), radius: 18, x: 5)
                .accessibilityHidden(progress < 0.01)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .global)
                        .onChanged { handleOpenDrawerDragChanged($0, width: width) }
                        .onEnded { handleOpenDrawerDragEnded($0, width: width) }
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(progress > 0 && pullController.pull == 0)
        .accessibilityHidden(progress == 0 || pullController.pull > 0)
    }

    private func updateArtworkAndTheme() async {
        guard !Task.isCancelled else { return }
        let request = artworkRequests.begin(trackID: playbackService.queue.current?.musicID)
        guard let track = playbackService.queue.current else {
            playbackService.updateNowPlayingArtwork(nil)
            withAnimation(AppMotion.emphasized(duration: AppMotion.long, reduceMotion: reduceMotion)) {
                themeState.update(accentHex: nil)
            }
            return
        }

        let store = LibraryStore(context: modelContext)
        playbackService.updateNowPlayingArtwork(nil)
        let image: UIImage?
        if let artworkService {
            image = try? await artworkService.image(for: track)
        } else {
            image = nil
        }
        let committed = artworkRequests.commit(request, currentTrackID: playbackService.queue.current?.musicID) {
            playbackService.updateNowPlayingArtwork(image)
            let accentHex = image.flatMap(ArtworkPalette.accentHex(from:))
            try? store.cacheAccentHex(accentHex, for: track)
            withAnimation(AppMotion.emphasized(duration: AppMotion.long, reduceMotion: reduceMotion)) {
                themeState.update(accentHex: accentHex)
            }
        }
        guard committed else { return }

        await refreshCurrentTrackMetadataIfNeeded(track, store: store, request: request)
    }

    private func refreshCurrentTrackMetadataIfNeeded(
        _ track: Track,
        store: LibraryStore,
        request: ArtworkRequestGate.Request
    ) async {
        guard let trackDetailRefreshCoordinator else { return }
        do {
            let outcome = try await trackDetailRefreshCoordinator.refresh(track, store: store)
            guard case let .refreshed(refreshed) = outcome else { return }
            try Task.checkCancellation()
            artworkRequests.commit(request, currentTrackID: playbackService.queue.current?.musicID) {
                playbackService.updateTrackMetadata(refreshed)
            }
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    /// 冷启动预热：当前曲目与收藏前 3 首的封面，减少首屏空图。
    private func warmUpCaches() async {
        guard let artworkService else { return }
        if let current = playbackService.queue.current {
            _ = try? await artworkService.image(for: current)
        }
        let store = LibraryStore(context: modelContext)
        if let playlist = try? store.ensurePersonalPlaylist() {
            for item in playlist.orderedItems.prefix(3) {
                guard let track = item.track.track else { continue }
                _ = try? await artworkService.image(for: track)
            }
        }
        PerfLog.mark("warm_done")
    }

    private func recordRecentTrack() async {
        guard let successfullyLoadedTrackID,
              let track = playbackService.queue.current,
              track.musicID == successfullyLoadedTrackID else { return }
        _ = try? LibraryStore(context: modelContext).recordRecent(track)
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "sonar" else { return }
        switch url.host {
        case "nowplaying":
            if playbackService.queue.current != nil {
                closeSettingsDrawer()
                playerSurface = .artwork
                pullController.open(reduceMotion: reduceMotion)
            } else {
                toastCenter.show("暂无播放中的歌曲")
            }
        case "play-favorites":
            Task { @MainActor in
                closeSettingsDrawer()
                let store = LibraryStore(context: modelContext)
                do {
                    let playlist = try store.ensurePersonalPlaylist()
                    let tracks = playlist.orderedItems.compactMap { $0.track.track }
                    guard !tracks.isEmpty else {
                        toastCenter.show("\(playlist.name) 暂无歌曲")
                        return
                    }
                    await playbackService.shuffleAndPlay(tracks, activePlaylistID: playlist.id)
                    playerSurface = .artwork
                    pullController.open(reduceMotion: reduceMotion)
                } catch {
                    toastCenter.show("无法获取收藏歌单")
                }
            }
        default:
            break
        }
    }
}
