import SwiftUI
import SwiftData

@main
struct SonarApp: App {
    @State private var bootstrap: SonarBootstrap

    init() {
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
    let themeState: SonarThemeState
    let uiPreferences: UIPlaybackPreferences
    let toastCenter: ToastCenter
    let confirmationCenter: ConfirmationCenter

    init() {
        let credentials = BuildCredentialStore()
        let breaker = ChkszCircuitBreaker()
        let chkszAPI = ChkszAPIClient(credentials: credentials, breaker: breaker)
        let chkszNetEase = ChkszNetEaseClient(api: chkszAPI)
        let runtime = FallbackSourceRuntime(
            primary: JavaScriptSourceRuntime(),
            neteaseFallback: chkszNetEase
        )
        sourceRuntime = runtime
        let resolver = PlaybackResolverPipeline.make(
            primary: PlaybackURLResolver(
                credentials: credentials,
                breaker: breaker,
                chkszAPI: chkszAPI,
                wyFallback: chkszNetEase
            ),
            sourceRuntime: runtime
        )
        playbackService = PlaybackService(
            resolver: resolver
        )
        artworkService = try? ArtworkService(sourceRuntime: runtime)
        trackDetailRefreshCoordinator = TrackDetailRefreshCoordinator(sourceRuntime: runtime)
        lyricsService = LyricsService(sourceRuntime: runtime)
        themeState = SonarThemeState()
        uiPreferences = UIPlaybackPreferences()
        toastCenter = ToastCenter()
        confirmationCenter = ConfirmationCenter()
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
            .environment(\.artworkService, services.artworkService)
            .environment(\.sourceRuntime, services.sourceRuntime)
            .environment(\.trackDetailRefreshCoordinator, services.trackDetailRefreshCoordinator)
            .environment(\.lyricsService, services.lyricsService)
    }
}

private struct ThemedRootView: View {
    let sourceRuntime: SourceRuntime

    @Environment(SonarThemeState.self) private var themeState
    @Environment(UIPlaybackPreferences.self) private var uiPreferences
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let scheme = themeState.scheme(for: systemColorScheme)
        let shouldReduceMotion = reduceMotion || !uiPreferences.motionEnabled

        RootView(sourceRuntime: sourceRuntime)
            .environment(\.m3Scheme, scheme)
            .environment(\.playerPalette, PlayerPalette(scheme: scheme))
            .environment(\.sonarReduceMotion, shouldReduceMotion)
            .preferredColorScheme(themeState.appearanceMode.colorScheme)
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
