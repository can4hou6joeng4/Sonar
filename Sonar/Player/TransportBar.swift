import SwiftUI

extension PlaybackService.PlaybackMode {
    var title: String {
        switch self {
        case .sequence: "列表循环"
        case .shuffle: "随机播放"
        case .repeatOne: "单曲循环"
        }
    }

    var systemImage: String {
        switch self {
        case .sequence: "repeat"
        case .shuffle: "shuffle"
        case .repeatOne: "repeat.1"
        }
    }

    var next: Self {
        switch self {
        case .sequence: .repeatOne
        case .repeatOne: .shuffle
        case .shuffle: .sequence
        }
    }
}

enum PlaybackStatusPresentation {
    static func text(for state: PlaybackService.State) -> String {
        switch state {
        case .idle:
            return "尚未开始播放"
        case .loading:
            return "正在连接音频"
        case .playing:
            return "正在播放"
        case .paused:
            return "已暂停"
        case let .failed(message):
            let reason = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return reason.isEmpty ? "播放失败，点按重试" : "播放失败：\(reason)"
        }
    }
}

struct TransportBar: View {
    var onOpenQueue: (() -> Void)? = nil
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @State private var dragValue: TimeInterval?

    private var displayedElapsed: TimeInterval { dragValue ?? playbackService.elapsed }
    private var isEnabled: Bool { playbackService.queue.current != nil }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                PlayerProgressSlider(
                    value: displayedElapsed,
                    duration: playbackService.duration,
                    onEditing: { dragValue = $0 },
                    onCommit: commitSeek
                )
                .frame(height: 28)

                HStack {
                    timecode(displayedElapsed)
                    Spacer()
                    timecode(playbackService.duration)
                }
            }
            .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
            .padding(.top, 12)

            PlaybackStatusLine()

            HStack(spacing: 0) {
                Button {
                    AppHaptics.light()
                    let next = playbackService.playbackMode.next
                    playbackService.setPlaybackMode(next)
                    toastCenter.show(next.title)
                } label: {
                    Image(systemName: playbackService.playbackMode.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bounce)
                .frame(maxWidth: .infinity)
                .foregroundStyle(isEnabled ? NCMDesignTokens.Player.secondaryInk : NCMDesignTokens.Player.tertiaryInk)
                .disabled(!isEnabled)
                .accessibilityLabel("播放模式，\(playbackService.playbackMode.title)")
                .accessibilityIdentifier("player-playback-mode")

                transportButton("backward.end.fill", size: 24, label: "上一首") {
                    Task { await playbackService.previous() }
                }

                Button(action: performPrimaryPlaybackAction) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 60, height: 60)

                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 60, height: 60)

                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.40), Color.white.opacity(0.10)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                            .frame(width: 60, height: 60)
                            .shadow(color: .black.opacity(0.24), radius: 10, y: 4)

                        if playbackService.state == .loading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(NCMDesignTokens.Player.primaryInk)
                                .frame(width: 26, height: 26)
                        } else {
                            Image(systemName: playbackIcon)
                                .font(.system(size: 26, weight: .bold))
                                .offset(x: playbackService.state == .playing ? 0 : 1.5)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .frame(width: 66, height: 66)
                    .contentShape(Circle())
                }
                .buttonStyle(.bounce(scale: 0.90, opacity: 0.90, haptic: true))
                .frame(maxWidth: .infinity)
                .foregroundStyle(isEnabled ? NCMDesignTokens.Player.primaryInk : NCMDesignTokens.Player.tertiaryInk)
                .disabled(!isEnabled)
                .accessibilityLabel(playbackControlLabel)
                .accessibilityIdentifier("player-play-pause-button")

                transportButton("forward.end.fill", size: 24, label: "下一首") {
                    Task { await playbackService.next() }
                }

                Button {
                    AppHaptics.light()
                    onOpenQueue?()
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bounce)
                .frame(maxWidth: .infinity)
                .foregroundStyle(isEnabled ? NCMDesignTokens.Player.secondaryInk : NCMDesignTokens.Player.tertiaryInk)
                .disabled(!isEnabled)
                .accessibilityLabel("待播放")
                .accessibilityIdentifier("player-queue-button")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        }
    }

    private var playbackIcon: String {
        switch playbackService.state {
        case .failed:
            return "arrow.clockwise"
        case .playing:
            return "pause.fill"
        case .idle, .paused:
            return hasReachedEnd ? "arrow.counterclockwise" : "play.fill"
        case .loading:
            return "play.fill"
        }
    }

    private var hasReachedEnd: Bool {
        playbackService.duration.isFinite
            && playbackService.elapsed.isFinite
            && playbackService.duration > 0
            && playbackService.elapsed >= playbackService.duration - 0.25
    }

    private var playbackControlLabel: String {
        switch playbackService.state {
        case .playing:
            return "暂停"
        case .loading:
            return playbackService.playbackRequested ? "暂停加载" : "播放"
        case .failed:
            return "重试播放"
        case .idle, .paused:
            return hasReachedEnd ? "重新播放" : "播放"
        }
    }

    private func timecode(_ value: TimeInterval) -> some View {
        Text(format(value))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
    }

    private func transportButton(
        _ image: String,
        size: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            AppHaptics.light()
            action()
        }) {
            Image(systemName: image)
                .font(.system(size: size, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bounce(scale: 0.88, opacity: 0.82, haptic: false))
        .frame(maxWidth: .infinity)
        .foregroundStyle(isEnabled ? NCMDesignTokens.Player.primaryInk : NCMDesignTokens.Player.tertiaryInk)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func commitSeek(_ value: TimeInterval) {
        dragValue = nil
        Task { await playbackService.seek(to: value) }
    }

    private func performPrimaryPlaybackAction() {
        AppHaptics.medium()
        Task {
            if case .failed = playbackService.state {
                await playbackService.retryCurrent()
            } else if hasReachedEnd,
                      playbackService.state == .idle || playbackService.state == .paused {
                await playbackService.seek(to: 0)
                await playbackService.play()
            } else {
                await playbackService.togglePlayback()
            }
        }
    }

    private func format(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }
}

private struct PlaybackStatusLine: View {
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.sonarReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch playbackService.state {
            case .loading, .failed:
                ViewThatFits(in: .horizontal) {
                    playbackStatus(showsFailureReason: true)
                        .fixedSize(horizontal: true, vertical: false)
                    playbackStatus(showsFailureReason: false)
                }
                .frame(maxWidth: .infinity, minHeight: 28)
                .accessibilityLabel(PlaybackStatusPresentation.text(for: playbackService.state))
                .accessibilityIdentifier("player-playback-status")
            case .idle, .playing, .paused:
                Color.clear.frame(height: 6)
                    .accessibilityIdentifier("player-playback-status")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
    }

    @ViewBuilder
    private func playbackStatus(showsFailureReason: Bool) -> some View {
        Group {
            switch playbackService.state {
            case .failed:
                Button(action: retryPlayback) {
                    statusLabel(
                        systemImage: "arrow.clockwise",
                        text: showsFailureReason
                            ? PlaybackStatusPresentation.text(for: playbackService.state)
                            : "失败，重试"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("重新解析并播放当前歌曲")
            case .loading:
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(NCMDesignTokens.Player.secondaryInk)
                    Text(PlaybackStatusPresentation.text(for: playbackService.state))
                }
            case .idle, .playing, .paused:
                statusLabel(
                    systemImage: stateSystemImage,
                    text: PlaybackStatusPresentation.text(for: playbackService.state)
                )
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }

    private var playbackModeButton: some View {
        Button {
            playbackService.setPlaybackMode(playbackService.playbackMode.next)
        } label: {
            ViewThatFits(in: .horizontal) {
                Label(
                    playbackService.playbackMode.title,
                    systemImage: playbackService.playbackMode.systemImage
                )
                .fixedSize(horizontal: true, vertical: false)

                VStack(spacing: 1) {
                    Image(systemName: playbackService.playbackMode.systemImage)
                    Text(playbackService.playbackMode.title)
                }
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .frame(width: 104)
            .frame(minHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentTransition(.symbolEffect(.replace))
        .animation(
            AppMotion.emphasized(duration: AppMotion.short, reduceMotion: reduceMotion),
            value: playbackService.playbackMode
        )
        .accessibilityLabel("播放模式，\(playbackService.playbackMode.title)")
        .accessibilityHint("双击切换播放模式")
        .accessibilityIdentifier("player-playback-mode")
    }

    private var stateSystemImage: String {
        switch playbackService.state {
        case .playing: "waveform"
        case .paused: "pause.fill"
        case .idle, .loading, .failed: "play.fill"
        }
    }

    private func statusLabel(systemImage: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
            Text(text)
        }
        .contentShape(Rectangle())
    }

    private func retryPlayback() {
        Task { await playbackService.retryCurrent() }
    }
}

private struct PlayerProgressSlider: View {
    let value: TimeInterval
    let duration: TimeInterval
    let onEditing: (TimeInterval) -> Void
    let onCommit: (TimeInterval) -> Void

    @State private var isDragging = false

    private var progress: CGFloat {
        guard duration > 0 else { return 0 }
        return min(max(value / duration, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(NCMDesignTokens.Player.progressTrack)
                    .frame(height: 3)
                Capsule()
                    .fill(NCMDesignTokens.Player.primaryInk)
                    .frame(width: width * progress, height: 3)
                Circle()
                    .fill(.white)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .scaleEffect(isDragging ? 1.5 : 1)
                    .offset(x: min(max(width * progress - 5.5, -0.5), width - 10.5))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        onEditing(value(at: gesture.location.x, width: width))
                    }
                    .onEnded { gesture in
                        isDragging = false
                        onCommit(value(at: gesture.location.x, width: width))
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(Int(progress * 100))%")
        .accessibilityIdentifier("player-progress-slider")
        .accessibilityAdjustableAction { direction in
            let delta: TimeInterval = direction == .increment ? 5 : -5
            onCommit(min(max(value + delta, 0), max(duration, 0)))
        }
    }

    private func value(at x: CGFloat, width: CGFloat) -> TimeInterval {
        min(max(x / width, 0), 1) * max(duration, 0)
    }
}
