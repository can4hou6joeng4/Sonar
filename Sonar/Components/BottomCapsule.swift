import Observation
import QuartzCore
import SwiftUI

enum CapsuleScrollTracking {
    static let coordinateSpace = "sonar-capsule-scroll"
}

struct CapsuleScrollReporter {
    let update: @MainActor (CGFloat) -> Void
    let settle: @MainActor () -> Void

    static let inactive = CapsuleScrollReporter(update: { _ in }, settle: {})
}

private struct CapsuleScrollReporterKey: EnvironmentKey {
    static let defaultValue = CapsuleScrollReporter.inactive
}

extension EnvironmentValues {
    var capsuleScrollReporter: CapsuleScrollReporter {
        get { self[CapsuleScrollReporterKey.self] }
        set { self[CapsuleScrollReporterKey.self] = newValue }
    }
}

struct CapsuleScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CapsuleScrollMarker: View {
    var body: some View {
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
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

@MainActor
@Observable
final class BottomCapsuleScrollController {
    private(set) var reveal = 1.0
    private(set) var lastDelta: CGFloat = 0

    static func settleTarget(reveal: Double, lastDelta: CGFloat) -> Double {
        if lastDelta > 0.1 {
            return reveal <= PlayerPullMetrics.hideThreshold ? 0 : 1
        }
        if lastDelta < -0.1 {
            return reveal >= PlayerPullMetrics.revealThreshold ? 1 : 0
        }
        return reveal >= 0.5 ? 1 : 0
    }

    func update(delta: CGFloat, travelExtent: CGFloat) {
        guard travelExtent > 0, delta.isFinite else { return }
        reveal = min(max(reveal - Double(delta / travelExtent), 0), 1)
        lastDelta = delta
    }

    func settle(reduceMotion: Bool) {
        let target = Self.settleTarget(reveal: reveal, lastDelta: lastDelta)
        let remaining = abs(reveal - target)
        lastDelta = 0
        guard !reduceMotion, remaining >= 0.001 else {
            show(target, disablesAnimations: true)
            return
        }
        withAnimation(
            AppMotion.emphasized(
                duration: PlayerPullMetrics.settleDuration(remaining: remaining),
                reduceMotion: false
            )
        ) {
            reveal = target
        }
    }

    func showImmediately() {
        lastDelta = 0
        show(1, disablesAnimations: true)
    }

    private func show(_ target: Double, disablesAnimations: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = disablesAnimations
        withTransaction(transaction) { reveal = target }
    }
}

struct BottomCapsule: View {
    private enum Page {
        case navigation
        case miniPlayer

        mutating func toggle() {
            self = self == .navigation ? .miniPlayer : .navigation
        }
    }

    private enum GestureAxis {
        case horizontal
        case vertical
    }

    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.m3Scheme) private var scheme

    let selectedTab: ShellTab
    let availableWidth: CGFloat
    let safeBottom: CGFloat
    let pullController: PlayerPullController
    let scrollController: BottomCapsuleScrollController
    let onSelectTab: (ShellTab) -> Void

    @State private var page: Page = .navigation
    @State private var switchProgress = 0.0
    @State private var gestureAxis: GestureAxis?
    @State private var lastTranslation = CGSize.zero
    @State private var lastTimestamp: CFTimeInterval?
    @State private var velocityY: CGFloat = 0

    private var actionWidth: CGFloat {
        min(max(floor((availableWidth - 38) / 4), 48), 76)
    }

    private var capsuleWidth: CGFloat { actionWidth * 4 + 10 }
    private var capsuleHeight: CGFloat { 58 }
    private var travelExtent: CGFloat { capsuleHeight + max(safeBottom, 10) }
    private var pageDirection: CGFloat { page == .navigation ? -1 : 1 }
    private var combinedReveal: Double {
        min(pullController.toolbarReveal, scrollController.reveal)
    }
    private var toolbarOpacity: Double {
        let normalized = min(max(combinedReveal / 0.34, 0), 1)
        return 1 - pow(1 - normalized, 2)
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(scheme.capsuleBackground)

            Capsule()
                .strokeBorder(scheme.outlineVariant.opacity(0.52), lineWidth: 1)

            capsulePages

            CapsuleProgressRing()
                .allowsHitTesting(false)
        }
        .frame(width: capsuleWidth, height: capsuleHeight)
        .clipShape(Capsule())
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.18 : 0.08),
            radius: 28,
            y: 10
        )
        .contentShape(Capsule())
        .simultaneousGesture(capsuleGesture)
        .offset(y: CGFloat(1 - combinedReveal) * travelExtent)
        .opacity(toolbarOpacity)
        .allowsHitTesting(combinedReveal > 0.02)
        .padding(.bottom, max(safeBottom, 10))
    }

    private var capsulePages: some View {
        ZStack {
            NavigationCapsulePage(
                selectedTab: selectedTab,
                actionWidth: actionWidth,
                onSelectTab: onSelectTab
            )
            .opacity(pageOpacity(for: .navigation))
            .offset(x: pageOffset(for: .navigation))
            .allowsHitTesting(pageAllowsHitTesting(.navigation))

            MiniPlayerCapsulePage(onOpenPlayer: openPlayer)
                .opacity(pageOpacity(for: .miniPlayer))
                .offset(x: pageOffset(for: .miniPlayer))
                .allowsHitTesting(pageAllowsHitTesting(.miniPlayer))
        }
        .padding(.horizontal, 5)
    }

    private var capsuleGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }

    private func pageOpacity(for candidate: Page) -> Double {
        candidate == page ? 1 - switchProgress : switchProgress
    }

    private func pageOffset(for candidate: Page) -> CGFloat {
        if candidate == page {
            return pageDirection * 20 * switchProgress
        }
        return -pageDirection * 20 * (1 - switchProgress)
    }

    private func pageAllowsHitTesting(_ candidate: Page) -> Bool {
        candidate == page ? switchProgress < 0.5 : switchProgress >= 0.5
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let translation = value.translation
        pullController.warm()
        if gestureAxis == nil {
            guard abs(translation.width) >= 5 || abs(translation.height) >= 5 else { return }
            // 斜向手势优先归入垂直上拉，保持播放器入口稳定。
            gestureAxis = abs(translation.height) >= abs(translation.width) ? .vertical : .horizontal
            lastTranslation = .zero
            lastTimestamp = CACurrentMediaTime()
            if gestureAxis == .vertical {
                pullController.beginInteraction()
            }
        }

        let now = CACurrentMediaTime()
        if gestureAxis == .vertical {
            let deltaY = translation.height - lastTranslation.height
            if let lastTimestamp {
                let interval = now - lastTimestamp
                if interval > 0 { velocityY = deltaY / interval }
            }
            pullController.update(translationY: translation.height, viewportHeight: availableViewportHeight)
        } else {
            let signedTravel = translation.width * pageDirection
            switchProgress = min(max(Double(signedTravel / 160), 0), 1)
        }
        lastTranslation = translation
        lastTimestamp = now
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let finalDelta = CGSize(
            width: value.translation.width - lastTranslation.width,
            height: value.translation.height - lastTranslation.height
        )
        switch gestureAxis {
        case .vertical:
            pullController.endInteraction(
                velocityY: velocityY,
                lastDeltaY: abs(finalDelta.height) > 0.01 ? finalDelta.height : lastTranslation.height,
                reduceMotion: reduceMotion
            )
        case .horizontal:
            settleCapsule(lastDeltaX: abs(finalDelta.width) > 0.01 ? finalDelta.width : lastTranslation.width)
        case nil:
            break
        }
        resetGestureSamples()
    }

    private var availableViewportHeight: CGFloat {
        max(UIScreen.main.bounds.height, 1)
    }

    private func settleCapsule(lastDeltaX: CGFloat) {
        let directionalDelta = lastDeltaX * pageDirection
        let target: Double
        if directionalDelta > 0 {
            target = switchProgress >= PlayerPullMetrics.revealThreshold ? 1 : 0
        } else if directionalDelta < 0 {
            target = switchProgress <= PlayerPullMetrics.hideThreshold ? 0 : 1
        } else {
            target = switchProgress >= 0.5 ? 1 : 0
        }
        let remaining = abs(switchProgress - target)
        guard !reduceMotion, remaining >= 0.001 else {
            finishCapsule(target: target)
            return
        }
        let animation = AppMotion.emphasized(
            duration: PlayerPullMetrics.settleDuration(remaining: remaining),
            reduceMotion: false
        )
        withAnimation(animation) {
            switchProgress = target
        } completion: {
            finishCapsule(target: target)
        }
    }

    private func finishCapsule(target: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if target == 1 { page.toggle() }
            switchProgress = 0
        }
    }

    private func resetGestureSamples() {
        gestureAxis = nil
        lastTranslation = .zero
        lastTimestamp = nil
        velocityY = 0
    }

    private func openPlayer() {
        pullController.open(reduceMotion: reduceMotion)
    }
}

private struct NavigationCapsulePage: View {
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme

    let selectedTab: ShellTab
    let actionWidth: CGFloat
    let onSelectTab: (ShellTab) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(scheme.secondaryContainer)
                .frame(width: actionWidth, height: 50)
                .offset(x: CGFloat(selectedTab.rawValue) * actionWidth)
                .animation(
                    AppMotion.emphasized(duration: AppMotion.medium, reduceMotion: reduceMotion),
                    value: selectedTab
                )

            HStack(spacing: 0) {
                ForEach(ShellTab.allCases) { tab in
                    Button {
                        onSelectTab(tab)
                    } label: {
                        VStack(spacing: 1) {
                            Group {
                                if tab == .player, playbackService.state == .playing {
                                    PlayingEqualizerGlyph(color: iconColor(for: tab))
                                } else {
                                    Image(systemName: tab.systemImage)
                                        .font(.system(size: 22, weight: .medium))
                                }
                            }
                            .frame(width: 24, height: 24)
                            Text(tab.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(iconColor(for: tab))
                        .frame(width: actionWidth, height: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CapsulePressButtonStyle())
                    .accessibilityLabel(tab.title)
                    .accessibilityIdentifier(tab.accessibilityIdentifier)
                }
            }
        }
        .frame(width: actionWidth * 4, height: 58)
    }

    @Environment(\.sonarReduceMotion) private var reduceMotion

    private func iconColor(for tab: ShellTab) -> Color {
        tab == selectedTab ? scheme.onSecondaryContainer : scheme.onSurfaceVariant
    }
}

private struct MiniPlayerCapsulePage: View {
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme

    let onOpenPlayer: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 240
            let artworkSize: CGFloat = compact ? 36 : 44
            let controlSize: CGFloat = compact ? 36 : 40

            HStack(spacing: 0) {
                Button(action: onOpenPlayer) {
                    HStack(spacing: 10) {
                        SpinningCoverArt(
                            track: playbackService.queue.current,
                            size: artworkSize,
                            isPlaying: playbackService.state == .playing
                        )
                        .contentShape(Circle())
                        .accessibilityIdentifier("mini-player-cover")

                        VStack(alignment: .leading, spacing: 1) {
                            Text(playbackService.queue.current?.title ?? "暂无播放")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(scheme.onSurface)
                                .lineLimit(1)
                                .frame(height: 13 * 1.2)
                            if !compact {
                                Text(playbackService.queue.current?.artist ?? "选择一首歌曲开始播放")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(scheme.onSurfaceVariant)
                                    .lineLimit(1)
                                    .frame(height: 10.5 * 1.2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: artworkSize, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开播放页")
                .accessibilityIdentifier("mini-player-title")

                MiniPlayerControl(
                    systemImage: "backward.fill",
                    label: "上一首",
                    identifier: "mini-player-previous",
                    size: controlSize
                ) {
                    Task { await playbackService.previous() }
                }
                MiniPlayerControl(
                    systemImage: playbackService.state == .playing ? "pause.fill" : "play.fill",
                    label: playbackService.state == .playing ? "暂停" : "播放",
                    identifier: "mini-player-play-pause",
                    size: controlSize
                ) {
                    Task { await playbackService.togglePlayback() }
                }
                MiniPlayerControl(
                    systemImage: "forward.fill",
                    label: "下一首",
                    identifier: "mini-player-next",
                    size: controlSize
                ) {
                    Task { await playbackService.next() }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MiniPlayerControl: View {
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme

    let systemImage: String
    let label: String
    let identifier: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: systemImage.contains("play") || systemImage.contains("pause") ? 20 : 17, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(CapsulePressButtonStyle())
        .foregroundStyle(scheme.onSurfaceVariant)
        .disabled(playbackService.queue.current == nil || playbackService.state == .loading)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

private struct CapsuleProgressRing: View {
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme

    private var progress: Double {
        guard playbackService.duration > 0 else { return 0 }
        return min(max(playbackService.elapsed / playbackService.duration, 0), 1)
    }

    var body: some View {
        Capsule()
            .trim(from: 0, to: progress)
            .stroke(
                scheme.primary.opacity(0.72),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
            )
            .padding(1.2)
            .accessibilityHidden(true)
    }
}

private struct PlayingEqualizerGlyph: View {
    @Environment(\.sonarReduceMotion) private var reduceMotion

    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, _ in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<4 {
                    let phase = (seconds / 0.92 + Double(index) * 0.19) * 2 * .pi
                    let height = reduceMotion ? [9.0, 15.0, 12.0, 17.0][index] : 7.5 + (sin(phase) + 1) * 5.2
                    let x = [4.5, 9.5, 14.5, 19.5][index]
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 12 - height / 2))
                    path.addLine(to: CGPoint(x: x, y: 12 + height / 2))
                    context.stroke(
                        path,
                        with: .color(color),
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                    )
                }
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

private struct CapsulePressButtonStyle: ButtonStyle {
    @Environment(\.sonarReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(AppMotion.expressiveSpring(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
