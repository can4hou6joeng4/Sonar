import SwiftUI
import SwiftData

@main
struct SonarApp: App {
    @State private var bootstrap: SonarBootstrap

    init() {
        PerfLog.mark("app_init")
        #if DEBUG
        var failFirstOpen = ProcessInfo.processInfo.arguments.contains("-sonar-test-store-failure-once")
        _bootstrap = State(initialValue: SonarBootstrap(open: {
            if failFirstOpen {
                failFirstOpen = false
                throw CocoaError(.fileReadCorruptFile)
            }
            return try SonarModelContainer.make()
        }))
        #else
        _bootstrap = State(initialValue: SonarBootstrap())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if let container = bootstrap.container {
                ReadySonarView()
                    .modelContainer(container)
            } else {
                LibraryRecoveryView(retry: bootstrap.retry)
            }
        }
    }
}

@MainActor @Observable
private final class SonarServices {
    let sourceRuntime: SourceRuntime
    let playbackService: PlaybackService
    let artworkService: ArtworkService?
    let trackDetailRefreshCoordinator: TrackDetailRefreshCoordinator
    let lyricsService: LyricsService
    let onlinePlaylistImporter: OnlinePlaylistImportService
    let themeState: SonarThemeState
    let uiPreferences: UIPlaybackPreferences
    let toastCenter: ToastCenter
    let confirmationCenter: ConfirmationCenter
    let sleepTimer: SleepTimer
    let networkStatus: NetworkStatusMonitor
    let audioCache: AudioCacheController

    init() {
        let credentials = BuildCredentialStore()
        let breaker = ChkszCircuitBreaker()
        let chkszAPI = ChkszAPIClient(credentials: credentials, breaker: breaker, requestTimeout: 15)
        let netease = ChkszNetEaseClient(api: chkszAPI)
        let direct = NetEaseWebClient()
        let runtime = NetEaseRuntimeDecorator(
            base: ChkszSourceRuntime(netease: netease),
            client: direct
        )
        sourceRuntime = runtime
        onlinePlaylistImporter = OnlinePlaylistImportService(chkszAPI: chkszAPI)
        // 每次解析直接返回 URL 与实际音质，可以安全共享最终结果，避免播放和缓存重复解析。
        let resolver = CachedPlaybackURLResolver(resolver: PlaybackResolverPipeline.make(
            primary: PlaybackURLResolver(
                credentials: credentials,
                breaker: breaker,
                chkszAPI: chkszAPI,
                netease: netease
            ),
            direct: NetEasePlaybackResolver(client: direct)
        ))
        let networkStatus = NetworkStatusMonitor()
        self.networkStatus = networkStatus
        let cacheStore = AudioCacheStore()
        let cacheDownloader = AudioCacheDownloader(
            store: cacheStore,
            resolver: resolver,
            isExpensive: { networkStatus.isExpensiveSnapshot },
            allowsDownloads: { networkStatus.allowsDownloadsSnapshot }
        )
        let audioCache = AudioCacheController(
            store: cacheStore,
            downloader: cacheDownloader,
            network: networkStatus
        )
        self.audioCache = audioCache
        playbackService = PlaybackService(
            resolver: resolver,
            audioCache: audioCache,
            networkStatus: networkStatus
        )
        artworkService = try? ArtworkService(sourceRuntime: runtime)
        trackDetailRefreshCoordinator = TrackDetailRefreshCoordinator(sourceRuntime: runtime)
        lyricsService = LyricsService(sourceRuntime: runtime)
        themeState = SonarThemeState()
        uiPreferences = UIPlaybackPreferences()
        toastCenter = ToastCenter()
        confirmationCenter = ConfirmationCenter()
        sleepTimer = SleepTimer()
    }

}

private struct ReadySonarView: View {
    @State private var services = SonarServices()

    var body: some View {
        ThemedRootView(sourceRuntime: services.sourceRuntime)
            .environment(services.playbackService)
            .environment(services.themeState)
            .environment(services.uiPreferences)
            .environment(services.toastCenter)
            .environment(services.confirmationCenter)
            .environment(services.sleepTimer)
            .environment(services.audioCache)
            .environment(\.artworkService, services.artworkService)
            .environment(\.sourceRuntime, services.sourceRuntime)
            .environment(\.trackDetailRefreshCoordinator, services.trackDetailRefreshCoordinator)
            .environment(\.lyricsService, services.lyricsService)
            .environment(\.onlinePlaylistImporter, services.onlinePlaylistImporter)
    }
}

private struct ThemedRootView: View {
    let sourceRuntime: SourceRuntime

    @Environment(SonarThemeState.self) private var themeState
    @Environment(UIPlaybackPreferences.self) private var uiPreferences
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let scheme = M3Scheme.spotlight(dark: themeState.appearanceMode.resolved(using: systemColorScheme) == .dark)
        let shouldReduceMotion = reduceMotion || !uiPreferences.motionEnabled

        RootView(sourceRuntime: sourceRuntime)
            .environment(\.m3Scheme, scheme)
            .environment(\.playerPalette, PlayerPalette(scheme: scheme))
            .environment(\.sonarReduceMotion, shouldReduceMotion)
            .tint(scheme.primary)
            .animation(
                AppMotion.emphasized(duration: AppMotion.long, reduceMotion: shouldReduceMotion),
                value: themeState.resolvedSeedHex
            )
            .animation(
                AppMotion.emphasized(duration: AppMotion.long, reduceMotion: shouldReduceMotion),
                value: themeState.appearanceMode
            )
    }
}
