import SwiftData
import SwiftUI
import UIKit

private enum ShellLayer: Hashable {
    case route
    case player
    case capsule
}

private enum ShellSheet: String, Identifiable {
    case queue

    var id: String { rawValue }
}

private struct ShellSafeAreaInsetsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

extension EnvironmentValues {
    var shellSafeAreaInsets: EdgeInsets {
        get { self[ShellSafeAreaInsetsKey.self] }
        set { self[ShellSafeAreaInsetsKey.self] = newValue }
    }
}

struct RootView: View {
    let sourceRuntime: SourceRuntime

    @Environment(PlaybackService.self) private var playbackService
    @Environment(SonarThemeState.self) private var themeState
    @Environment(\.artworkService) private var artworkService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.sonarReduceMotion) private var reduceMotion

    @State private var selectedTab: ShellTab = .home
    @State private var pullController = PlayerPullController()
    @State private var presentedSheet: ShellSheet?

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
            let safeBottom = proxy.safeAreaInsets.bottom

            ZStack(alignment: .bottom) {
                routeContent
                    .id(ShellLayer.route)
                    .accessibilityHidden(pullController.pull > 0)
                    .environment(\.shellSafeAreaInsets, proxy.safeAreaInsets)

                ZStack {
                    if pullController.playerMounted {
                        PlayerPage(
                            sourceRuntime: sourceRuntime,
                            pullController: pullController,
                            viewportHeight: proxy.size.height,
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
                    onOpenPlayer: { pullController.open(reduceMotion: reduceMotion) },
                    onOpenQueue: { presentedSheet = .queue }
                )
                .padding(.horizontal, NCMDesignTokens.Layout.miniPlayerHorizontalInset)
                .padding(.bottom, NCMDesignTokens.Layout.tabBarHeight + safeBottom + NCMDesignTokens.Layout.miniPlayerBottomSpacing)
                .offset(y: safeBottom)
                .opacity(pullController.toolbarReveal)
                .allowsHitTesting(pullController.pull == 0)
                .zIndex(NCMDesignTokens.Layer.miniPlayer)

                NCMTextTabBar(
                    selectedTab: selectedTab,
                    safeBottom: safeBottom,
                    onSelect: selectTab
                )
                .id(ShellLayer.capsule)
                .offset(y: safeBottom)
                .opacity(pullController.toolbarReveal)
                .allowsHitTesting(pullController.pull == 0)
                .zIndex(NCMDesignTokens.Layer.tabBar)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background {
            ZStack {
                scheme.appSurface
                if pullController.playerMounted {
                    FlowingLightBackground(track: playbackService.queue.current)
                        .opacity(pullController.pull)
                }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task(id: playbackService.queue.current?.musicID, updateArtworkAndTheme)
        .task(id: successfullyLoadedTrackID, recordRecentTrack)
        .overlay(alignment: .bottom) {
            ToastOverlay()
                .padding(.bottom, 156)
                .zIndex(NCMDesignTokens.Layer.toast)
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .queue:
                QueueSheet()
                    .presentationDetents([.fraction(0.72)])
                    .presentationDragIndicator(.hidden)
            }
        }
    }

    private var routeContent: some View {
        ZStack {
            NavigationStack {
                DiscoverView(runtime: sourceRuntime, isActive: selectedTab == .home)
            }
            .opacity(selectedTab == .home ? 1 : 0)
            .allowsHitTesting(selectedTab == .home)
            .accessibilityHidden(selectedTab != .home)

            NavigationStack {
                SongsView(isActive: selectedTab == .library)
            }
            .opacity(selectedTab == .library ? 1 : 0)
            .allowsHitTesting(selectedTab == .library)
            .accessibilityHidden(selectedTab != .library)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(
                height: NCMDesignTokens.Layout.miniPlayerHeight
                    + NCMDesignTokens.Layout.tabBarHeight
                    + NCMDesignTokens.Layout.bottomContentSpacing
            )
        }
    }

    private func selectTab(_ tab: ShellTab) {
        selectedTab = tab
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
    }

    private func recordRecentTrack() async {
        guard let successfullyLoadedTrackID,
              let track = playbackService.queue.current,
              track.musicID == successfullyLoadedTrackID else { return }
        _ = try? LibraryStore(context: modelContext).recordRecent(track)
    }
}
