import SwiftUI
import SwiftData

@main
struct SonarApp: App {
    private let modelContainer: ModelContainer
    private let sourceRuntime: JavaScriptSourceRuntime
    private let playbackService: PlaybackService
    private let artworkService: ArtworkService?
    private let themeState: SonarThemeState
    private let uiPreferences: UIPlaybackPreferences
    private let toastCenter: ToastCenter

    init() {
        do {
            modelContainer = try SonarModelContainer.make()
        } catch {
            fatalError("无法初始化 Sonar 数据库: \(error)")
        }
        let runtime = JavaScriptSourceRuntime()
        sourceRuntime = runtime
        let fallback = FallbackPlaybackURLResolver(
            primary: PlaybackURLResolver(credentials: BuildCredentialStore()),
            sourceRuntime: runtime
        )
        playbackService = PlaybackService(
            resolver: HighestAvailableQualityPlaybackURLResolver(resolver: fallback)
        )
        artworkService = try? ArtworkService(sourceRuntime: runtime)
        themeState = SonarThemeState()
        uiPreferences = UIPlaybackPreferences()
        toastCenter = ToastCenter()
    }

    var body: some Scene {
        WindowGroup {
            ThemedRootView(sourceRuntime: sourceRuntime)
                .environment(playbackService)
                .environment(themeState)
                .environment(uiPreferences)
                .environment(toastCenter)
                .environment(\.artworkService, artworkService)
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
