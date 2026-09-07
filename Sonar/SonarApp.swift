import SwiftUI
import SwiftData

@main
struct SonarApp: App {
    private let modelContainer: ModelContainer
    private let sourceRuntime: SourceRuntime
    private let playbackService: PlaybackService
    private let artworkService: ArtworkService?
    private let themeState: SonarThemeState
    private let uiPreferences: UIPlaybackPreferences
    private let toastCenter: ToastCenter
    private let confirmationCenter: ConfirmationCenter

    init() {
        let container: ModelContainer
        do {
            container = try SonarModelContainer.make()
        } catch {
            fatalError("无法初始化 Sonar 数据库: \(error)")
        }
        modelContainer = container
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
        themeState = SonarThemeState()
        uiPreferences = UIPlaybackPreferences()
        toastCenter = ToastCenter()
        confirmationCenter = ConfirmationCenter()
    }

    var body: some Scene {
        WindowGroup {
            ThemedRootView(sourceRuntime: sourceRuntime)
                .environment(playbackService)
                .environment(themeState)
                .environment(uiPreferences)
                .environment(toastCenter)
                .environment(confirmationCenter)
                .environment(\.artworkService, artworkService)
                .environment(\.sourceRuntime, sourceRuntime)
        }
        .modelContainer(modelContainer)
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
