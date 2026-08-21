import SwiftData
import SwiftUI
import UIKit

private enum ShellLayer: Hashable {
    case route
    case player
    case capsule
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

    @State private var selectedTab: ShellTab = .discover
    @State private var pullController = PlayerPullController()
    @State private var capsuleScrollController = BottomCapsuleScrollController()

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
            let travelExtent = 58 + max(safeBottom, 10)

            ZStack(alignment: .bottom) {
                routeContent
                    .id(ShellLayer.route)
                    .accessibilityHidden(pullController.pull > 0)
                    .environment(\.shellSafeAreaInsets, proxy.safeAreaInsets)
                    .environment(
                        \.capsuleScrollReporter,
                        CapsuleScrollReporter(
                            update: { delta in
                                capsuleScrollController.update(delta: delta, travelExtent: travelExtent)
                            },
                            settle: {
                                capsuleScrollController.settle(reduceMotion: reduceMotion)
                            }
                        )
                    )

                if pullController.playerMounted {
                    PlayerPage(
                        sourceRuntime: sourceRuntime,
                        pullController: pullController,
                        viewportHeight: proxy.size.height
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .offset(y: CGFloat(1 - pullController.pull) * proxy.size.height)
                    .allowsHitTesting(pullController.pull > 0)
                    .accessibilityHidden(pullController.pull == 0)
                    .id(ShellLayer.player)
                    .zIndex(1)
                }

                BottomCapsule(
                    selectedTab: selectedTab,
                    availableWidth: proxy.size.width,
                    safeBottom: safeBottom,
                    pullController: pullController,
                    scrollController: capsuleScrollController,
                    onSelectTab: selectTab
                )
                .id(ShellLayer.capsule)
                .zIndex(2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // 收起的播放器仍常驻在 Shell 下方；裁剪可避免它从底部安全区露出。
            .clipped()
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: selectedTab) { _, _ in
            capsuleScrollController.showImmediately()
        }
        .onChange(of: pullController.pull) { _, pull in
            if pull == 0 { capsuleScrollController.showImmediately() }
        }
        .task(id: playbackService.queue.current?.musicID, updateArtworkAndTheme)
        .task(id: successfullyLoadedTrackID, recordRecentTrack)
        .overlay(alignment: .bottom) {
            ToastOverlay()
                .padding(.bottom, 96)
                .zIndex(30)
        }
    }

    private var routeContent: some View {
        ZStack {
            NavigationStack {
                DiscoverView(runtime: sourceRuntime, isActive: selectedTab == .discover)
            }
            .opacity(selectedTab == .discover ? 1 : 0)
            .allowsHitTesting(selectedTab == .discover)
            .accessibilityHidden(selectedTab != .discover)

            NavigationStack {
                SongsView(isActive: selectedTab == .songs)
            }
            .opacity(selectedTab == .songs ? 1 : 0)
            .allowsHitTesting(selectedTab == .songs)
            .accessibilityHidden(selectedTab != .songs)

            NavigationStack {
                SettingsView()
            }
            .opacity(selectedTab == .settings ? 1 : 0)
            .allowsHitTesting(selectedTab == .settings)
            .accessibilityHidden(selectedTab != .settings)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 76)
        }
    }

    private func selectTab(_ tab: ShellTab) {
        if tab == .player {
            pullController.open(reduceMotion: reduceMotion)
            return
        }
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
