import SwiftUI

extension PlaybackService.PlaybackMode {
    var title: String {
        switch self {
        case .sequence: "顺序播放"
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
        let modes = Self.allCases
        return modes[(rawValue + 1) % modes.count]
    }
}

struct TransportBar: View {
    let onShowQueue: () -> Void

    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @State private var dragValue: TimeInterval?

    private var displayedElapsed: TimeInterval { dragValue ?? playbackService.elapsed }
    private var isEnabled: Bool { playbackService.queue.current != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                timecode(displayedElapsed, alignment: .leading)
                PlayerProgressSlider(
                    value: displayedElapsed,
                    duration: playbackService.duration,
                    onEditing: { dragValue = $0 },
                    onCommit: { value in
                        dragValue = nil
                        Task { await playbackService.seek(to: value) }
                    }
                )
                .frame(height: 22)
                timecode(playbackService.duration, alignment: .trailing)
            }
            .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
            .padding(.top, 14)

            HStack(spacing: 0) {
                transportButton(playbackService.playbackMode.systemImage, size: 20, frame: 44, label: playbackService.playbackMode.title) {
                    let mode = playbackService.playbackMode.next
                    playbackService.setPlaybackMode(mode)
                    toastCenter.show(mode.title)
                }
                .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
                .contentTransition(.symbolEffect(.replace))
                .animation(
                    AppMotion.emphasized(duration: AppMotion.short, reduceMotion: reduceMotion),
                    value: playbackService.playbackMode
                )
                .accessibilityIdentifier("player-playback-mode")

                Spacer(minLength: 0)

                transportButton("backward.end.fill", size: 26, frame: 52, label: "上一首") {
                    Task { await playbackService.previous() }
                }

                Spacer(minLength: 0)

                Button {
                    Task { await playbackService.togglePlayback() }
                } label: {
                    Group {
                        if playbackService.state == .loading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(NCMDesignTokens.Player.primaryInk)
                                .frame(width: 28, height: 28)
                        } else {
                            Image(systemName: playbackIcon)
                                .font(.system(size: 40, weight: .light))
                        }
                    }
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isEnabled ? NCMDesignTokens.Player.primaryInk : NCMDesignTokens.Player.tertiaryInk)
                .disabled(!isEnabled)
                .accessibilityLabel(playbackService.state == .playing ? "暂停" : "播放")
                .accessibilityIdentifier("player-play-pause-button")

                Spacer(minLength: 0)

                transportButton("forward.end.fill", size: 26, frame: 52, label: "下一首") {
                    Task { await playbackService.next() }
                }

                Spacer(minLength: 0)

                Button(action: onShowQueue) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 44, height: 44)
                        if !playbackService.queue.tracks.isEmpty {
                            Text(playbackService.queue.tracks.count > 99 ? "99+" : "\(playbackService.queue.tracks.count)")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(NCMDesignTokens.Player.primaryInk)
                                .padding(.horizontal, 3)
                                .frame(minWidth: 14, minHeight: 12)
                                .background(.white.opacity(0.22), in: Capsule())
                                .offset(x: 1, y: 3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(isEnabled ? NCMDesignTokens.Player.secondaryInk : NCMDesignTokens.Player.tertiaryInk)
                .disabled(!isEnabled)
                .accessibilityLabel("播放列表")
                .accessibilityIdentifier("player-queue-button")
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
        }
    }

    private var playbackIcon: String {
        if playbackService.duration > 0,
           playbackService.elapsed >= playbackService.duration - 0.25 {
            return "arrow.counterclockwise"
        }
        return playbackService.state == .playing ? "pause" : "play"
    }

    private func timecode(_ value: TimeInterval, alignment: Alignment) -> some View {
        Text(format(value))
            .font(.system(size: NCMDesignTokens.Typography.timecode).monospacedDigit())
            .foregroundStyle(NCMDesignTokens.Player.tertiaryInk)
            .frame(width: 32, alignment: alignment)
    }

    private func transportButton(
        _ image: String,
        size: CGFloat,
        frame: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: size, weight: .medium))
                .frame(width: frame, height: frame)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? NCMDesignTokens.Player.primaryInk : NCMDesignTokens.Player.tertiaryInk)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func format(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
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
                    .frame(height: 2)
                Capsule()
                    .fill(NCMDesignTokens.Player.primaryInk)
                    .frame(width: width * progress, height: 2)
                Circle()
                    .fill(.white)
                    .frame(width: 9, height: 9)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .scaleEffect(isDragging ? 1.5 : 1)
                    .offset(x: min(max(width * progress - 4.5, -0.5), width - 8.5))
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
    }

    private func value(at x: CGFloat, width: CGFloat) -> TimeInterval {
        min(max(x / width, 0), 1) * max(duration, 0)
    }
}
