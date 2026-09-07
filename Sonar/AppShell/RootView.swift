import SwiftData
import SwiftUI
import UIKit

private enum ShellLayer: Hashable {
    case route
    case player
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

extension EnvironmentValues {
    var shellSafeAreaInsets: EdgeInsets {
        get { self[ShellSafeAreaInsetsKey.self] }
        set { self[ShellSafeAreaInsetsKey.self] = newValue }
    }

    public var sourceRuntime: SourceRuntime? {
        get { self[SourceRuntimeEnvironmentKey.self] }
        set { self[SourceRuntimeEnvironmentKey.self] = newValue }
    }
}

enum ShellBottomLayout {
    static func contentReservation(hasCurrentTrack: Bool = true, safeAreaBottom: CGFloat) -> CGFloat {
        return NCMDesignTokens.Layout.miniPlayerHeight
            + NCMDesignTokens.Layout.bottomContentSpacing
            - MiniPlayerDockPresentation.safeAreaCompaction(safeAreaBottom: safeAreaBottom)
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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.sonarReduceMotion) private var reduceMotion

    @State private var pullController = PlayerPullController()
    @State private var playerSurface: PlayerSurface = .artwork
    @State private var drawerIsOpen = false
    @State private var drawerDragTranslation: CGFloat = 0
    @State private var edgeDrawerDragIsActive = false
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

            ZStack(alignment: .bottom) {
                routeContent(
                    drawerWidth: drawerWidth,
                    safeAreaBottom: proxy.safeAreaInsets.bottom
                )
                    .id(ShellLayer.route)
                    .accessibilityHidden(pullController.pull > 0 || drawerProgress > 0)
                    .environment(\.shellSafeAreaInsets, proxy.safeAreaInsets)
                    .allowsHitTesting(drawerProgress == 0 && pullController.pull == 0)

                if pullController.playerMounted {
                    FlowingLightBackground(track: playbackService.queue.current)
                        .opacity(pullController.pull)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(NCMDesignTokens.Layer.player - 1)
                }

                ZStack {
                    if pullController.playerMounted {
                        PlayerPage(
                            sourceRuntime: sourceRuntime,
                            pullController: pullController,
                            viewportHeight: proxy.size.height,
                            selectedSurface: $playerSurface,
                            onClose: { pullController.close(reduceMotion: reduceMotion) }
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(pullController.scale)
                        .opacity(pullController.opacity)
                        .offset(y: CGFloat(1 - pullController.pull) * proxy.size.height + pullController.translationY)
                        .id(ShellLayer.player)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                // The player stays mounted after closing; clip this layer without clipping bottom chrome.
                .clipped()
                .allowsHitTesting(pullController.pull > 0)
                .accessibilityHidden(pullController.pull == 0)
                .zIndex(NCMDesignTokens.Layer.player)

                NCMMiniPlayer(
                    safeAreaBottom: proxy.safeAreaInsets.bottom,
                    onOpenPlayer: {
                        guard playbackService.queue.current != nil else {
                            toastCenter.show("点按新歌开始播放")
                            return
                        }
                        closeSettingsDrawer()
                        playerSurface = .artwork
                        pullController.open(reduceMotion: reduceMotion)
                    },
                    onOpenQueue: {
                        guard playbackService.queue.current != nil else {
                            toastCenter.show("待播放列表暂无歌曲")
                            return
                        }
                        closeSettingsDrawer()
                        playerSurface = .queue
                        pullController.open(reduceMotion: reduceMotion)
                    }
                )
                .offset(y: ShellBottomLayout.miniPlayerVerticalOffset(
                    safeAreaBottom: proxy.safeAreaInsets.bottom
                ))
                .opacity(pullController.toolbarReveal)
                .allowsHitTesting(pullController.pull == 0 && drawerProgress == 0)
                .accessibilityHidden(pullController.pull > 0 || drawerProgress > 0)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(NCMDesignTokens.Layer.miniPlayer)

                settingsDrawer(width: drawerWidth, progress: drawerProgress)
                    .zIndex(25)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background {
            scheme.appSurface.ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task(id: playbackService.queue.current?.musicID, updateArtworkAndTheme)
        .task(id: successfullyLoadedTrackID, recordRecentTrack)
        .onChange(of: pullController.pull) { _, pull in
            if pull > 0 { closeSettingsDrawer() }
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
            DiscoverView(
                runtime: sourceRuntime,
                isActive: true,
                onOpenSettings: openSettingsDrawer,
                onSettingsDragChanged: { handleEdgeDrawerDragChanged($0, width: drawerWidth) },
                onSettingsDragEnded: { handleEdgeDrawerDragEnded($0, width: drawerWidth) }
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: ShellBottomLayout.contentReservation(
                hasCurrentTrack: hasCurrentTrack,
                safeAreaBottom: safeAreaBottom
            ))
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
        guard pullController.pull == 0 else { return }
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
        playbackService.updateNowPlayingArtwork(image)
        let accentHex = image.flatMap(ArtworkPalette.accentHex(from:))
        try? store.cacheAccentHex(accentHex, for: track)
        withAnimation(AppMotion.emphasized(duration: AppMotion.long, reduceMotion: reduceMotion)) {
            themeState.update(accentHex: accentHex)
        }

        await refreshCurrentTrackMetadataIfNeeded(track, store: store)
    }

    private func refreshCurrentTrackMetadataIfNeeded(_ track: Track, store: LibraryStore) async {
        guard track.highestKnownQuality == .standard else { return }
        guard let refreshed = try? await sourceRuntime.trackDetail(track) else { return }
        if refreshed.highestKnownQuality != .standard || TrackQualityOption.available(for: refreshed).count > 1 {
            await MainActor.run {
                playbackService.updateTrackMetadata(refreshed)
                _ = try? store.updateTrack(refreshed)
            }
        }
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
                        toastCenter.show("我喜欢的音乐暂无歌曲")
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
