import SwiftUI

enum MiniPlayerPresentation {
    static func progress(elapsed: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard elapsed.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return CGFloat(min(max(elapsed / duration, 0), 1))
    }

    static func timeSummary(elapsed: TimeInterval, duration: TimeInterval) -> String? {
        guard duration.isFinite, duration > 0 else { return nil }
        return "\(timecode(elapsed)) / \(timecode(duration))"
    }

    static func statusText(state: PlaybackService.State, artist: String) -> String {
        let artistText = artist.isEmpty ? "未知歌手" : artist
        switch state {
        case .loading:
            return "正在加载 · \(artistText)"
        case let .failed(message):
            return "播放失败：\(message)"
        case .playing:
            return "正在播放 · \(artistText)"
        case .paused:
            return "已暂停 · \(artistText)"
        case .idle:
            return "等待播放 · \(artistText)"
        }
    }

    static func accessibilityValue(
        state: PlaybackService.State,
        elapsed: TimeInterval,
        duration: TimeInterval
    ) -> String {
        let timeline = timeSummary(elapsed: elapsed, duration: duration)
        switch state {
        case .playing:
            return ["正在播放", timeline].compactMap { $0 }.joined(separator: "，")
        case .paused:
            return ["已暂停", timeline].compactMap { $0 }.joined(separator: "，")
        case .loading:
            return "正在加载音频"
        case let .failed(message):
            return "播放失败：\(message)，可以重试"
        case .idle:
            return "未开始播放"
        }
    }

    private static func timecode(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }
}

enum MiniPlayerDockPresentation {
    static let topCornerRadius: CGFloat = 22
    static let maximumSafeAreaCompaction: CGFloat = 8

    static func safeAreaCompaction(safeAreaBottom: CGFloat) -> CGFloat {
        min(max(safeAreaBottom, 0), maximumSafeAreaCompaction)
    }

    static func bottomCornerRadius(safeAreaBottom: CGFloat) -> CGFloat {
        safeAreaBottom > 0 ? 0 : topCornerRadius
    }

    static func height(rowHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        rowHeight + max(safeAreaBottom, 0)
    }
}

struct NCMMiniPlayer: View {
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.m3Scheme) private var scheme

    let safeAreaBottom: CGFloat
    let onOpenPlayer: () -> Void
    let onOpenQueue: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            dockShape
                .fill(.regularMaterial)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            dockShape
                .fill(scheme.surfaceContainerHigh.opacity(0.36))
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            topSeparator

            controls

            progressTrack
        }
        .frame(maxWidth: .infinity)
        .frame(height: dockHeight)
        .clipShape(dockShape)
        .shadow(color: .black.opacity(0.09), radius: 12, y: -3)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: onOpenPlayer) {
                HStack(spacing: 9) {
                    miniArtwork
                        .accessibilityIdentifier("mini-player-cover")

                    VStack(alignment: .leading, spacing: 1) {
                        Text(playbackService.queue.current?.title ?? "暂无播放")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(scheme.onSurface)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            if playbackService.state == .playing {
                                PlayingEqualizer(isAnimating: true, color: scheme.primary)
                            }

                            Text(statusText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)

                            Spacer(minLength: 4)

                            if let timelineText {
                                Text(timelineText)
                                    .monospacedDigit()
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(scheme.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("打开播放页")
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier("mini-player-title")

            Button(action: togglePlayback) {
                Group {
                    switch playbackService.state {
                    case .loading:
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(scheme.onSurface)
                    case .playing:
                        Image(systemName: "pause.circle")
                    case .failed:
                        Image(systemName: "arrow.clockwise.circle")
                    case .idle, .paused:
                        Image(systemName: "play.circle")
                    }
                }
                .font(.system(size: 28, weight: .regular))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: NCMDesignTokens.Layout.miniControlSize, height: NCMDesignTokens.Layout.miniControlSize)
            }
            .buttonStyle(.bounce)
            .foregroundStyle(playbackService.queue.current != nil ? scheme.onSurface : scheme.onSurface.opacity(0.45))
            .accessibilityLabel(playbackControlLabel)
            .accessibilityIdentifier("mini-player-play-pause")

            Button(action: onOpenQueue) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 23, weight: .regular))
                    .frame(width: NCMDesignTokens.Layout.miniControlSize, height: NCMDesignTokens.Layout.miniControlSize)
            }
            .buttonStyle(.bounce)
            .foregroundStyle(playbackService.queue.current != nil ? scheme.onSurface : scheme.onSurface.opacity(0.45))
            .accessibilityLabel("播放队列")
            .accessibilityIdentifier("mini-player-queue")
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(height: NCMDesignTokens.Layout.miniPlayerHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    let horizontal = value.translation.width
                    guard abs(horizontal) > 28,
                          abs(horizontal) > abs(value.translation.height) else { return }
                    if horizontal < 0 {
                        Task { await playbackService.next() }
                    } else {
                        Task { await playbackService.previous() }
                    }
                }
        )
    }

    private var dockHeight: CGFloat {
        MiniPlayerDockPresentation.height(
            rowHeight: NCMDesignTokens.Layout.miniPlayerHeight,
            safeAreaBottom: safeAreaBottom
        )
    }

    private var dockShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: MiniPlayerDockPresentation.topCornerRadius,
                bottomLeading: MiniPlayerDockPresentation.bottomCornerRadius(safeAreaBottom: safeAreaBottom),
                bottomTrailing: MiniPlayerDockPresentation.bottomCornerRadius(safeAreaBottom: safeAreaBottom),
                topTrailing: MiniPlayerDockPresentation.topCornerRadius
            ),
            style: .continuous
        )
    }

    private var topSeparator: some View {
        Rectangle()
            .fill(scheme.outlineVariant.opacity(0.42))
            .frame(height: 0.5)
            .padding(.horizontal, MiniPlayerDockPresentation.topCornerRadius)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var progressTrack: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(scheme.outlineVariant.opacity(0.42))
                    Capsule()
                        .fill(scheme.primary.opacity(0.82))
                        .frame(width: proxy.size.width * playbackProgress)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 16)
        }
        .frame(height: NCMDesignTokens.Layout.miniPlayerHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var playbackProgress: CGFloat {
        MiniPlayerPresentation.progress(
            elapsed: playbackService.elapsed,
            duration: playbackService.duration
        )
    }

    private var statusText: String {
        guard let track = playbackService.queue.current else {
            return "点按开启随心听"
        }
        return MiniPlayerPresentation.statusText(
            state: playbackService.state,
            artist: track.artist
        )
    }

    private var timelineText: String? {
        switch playbackService.state {
        case .playing, .paused:
            MiniPlayerPresentation.timeSummary(
                elapsed: playbackService.elapsed,
                duration: playbackService.duration
            )
        case .idle, .loading, .failed:
            nil
        }
    }

    private var accessibilityValue: String {
        MiniPlayerPresentation.accessibilityValue(
            state: playbackService.state,
            elapsed: playbackService.elapsed,
            duration: playbackService.duration
        )
    }

    private var playbackControlLabel: String {
        switch playbackService.state {
        case .playing: "暂停"
        case .loading: playbackService.playbackRequested ? "暂停加载" : "播放"
        case .failed: "重试播放"
        case .idle, .paused: "播放"
        }
    }

    private func togglePlayback() {
        guard playbackService.queue.current != nil else {
            AppHaptics.light()
            toastCenter.show("点按新歌开始播放")
            return
        }
        AppHaptics.medium()
        Task {
            if case .failed = playbackService.state {
                await playbackService.retryCurrent()
            } else {
                await playbackService.togglePlayback()
            }
            if case let .failed(message) = playbackService.state {
                toastCenter.show("播放失败：\(message)")
            }
        }
    }

    private var miniArtwork: some View {
        ZStack(alignment: .bottomTrailing) {
            PlayerArtwork(
                track: playbackService.queue.current,
                size: NCMDesignTokens.Layout.miniArtworkSize,
                cornerRadius: 8
            )
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)

            if playbackService.state == .playing {
                PlayingEqualizer(isAnimating: true, color: .white)
                    .padding(2.5)
                    .background(Color.black.opacity(0.60), in: RoundedRectangle(cornerRadius: 3.5))
                    .padding(2)
            }
        }
    }
}
