import SwiftUI

enum PlayerPlaybackMode: Int, CaseIterable {
    case sequence
    case shuffle
    case repeatOne

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
}

struct TransportBar: View {
    let onShowQueue: () -> Void

    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.playerPalette) private var palette
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @State private var dragValue: TimeInterval?
    @State private var mode: PlayerPlaybackMode = .sequence

    private var displayedElapsed: TimeInterval { dragValue ?? playbackService.elapsed }
    private var isEnabled: Bool { playbackService.queue.current != nil }

    var body: some View {
        VStack(spacing: 0) {
            PlayerProgressSlider(
                value: displayedElapsed,
                duration: playbackService.duration,
                onEditing: { dragValue = $0 },
                onCommit: { value in
                    dragValue = nil
                    Task { await playbackService.seek(to: value) }
                }
            )
            .frame(height: 28)

            HStack {
                Text(format(displayedElapsed))
                Spacer()
                Text(format(playbackService.duration))
            }
            .padding(.horizontal, 10)
            .font(.system(size: 15, weight: .medium).monospacedDigit())
            .foregroundStyle(palette.muted)

            HStack {
                transportButton(mode.systemImage, size: 25, label: mode.title) {
                    let cases = PlayerPlaybackMode.allCases
                    mode = cases[(mode.rawValue + 1) % cases.count]
                }
                .contentTransition(.symbolEffect(.replace))
                .animation(
                    AppMotion.emphasized(duration: AppMotion.short, reduceMotion: reduceMotion),
                    value: mode
                )

                transportButton("backward.end.fill", size: 38, label: "上一首") {
                    Task { await playbackService.previous() }
                }

                Button {
                    Task { await playbackService.togglePlayback() }
                } label: {
                    Group {
                        if playbackService.state == .loading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(palette.ink)
                                .frame(width: 22, height: 22)
                        } else {
                            Image(systemName: playbackIcon)
                                .font(.system(size: 56, weight: .regular))
                        }
                    }
                    .frame(width: 72, height: 72)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isEnabled ? palette.ink : palette.ink.opacity(0.22))
                .disabled(!isEnabled)
                .accessibilityLabel(playbackService.state == .playing ? "暂停" : "播放")
                .accessibilityIdentifier("player-play-pause-button")

                transportButton("forward.end.fill", size: 38, label: "下一首") {
                    Task { await playbackService.next() }
                }

                Button(action: onShowQueue) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 27, weight: .medium))
                            .frame(width: 48, height: 48)
                        if !playbackService.queue.tracks.isEmpty {
                            Text(playbackService.queue.tracks.count > 99 ? "99+" : "\(playbackService.queue.tracks.count)")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(palette.surface)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(palette.ink, in: Capsule())
                                .overlay(Capsule().stroke(palette.surface.opacity(0.92), lineWidth: 1.5))
                                .offset(x: 1, y: -1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(isEnabled ? palette.ink : palette.ink.opacity(0.22))
                .disabled(!isEnabled)
                .accessibilityLabel("播放列表")
                .accessibilityIdentifier("player-queue-button")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
        }
        .padding(.bottom, 2)
    }

    private var playbackIcon: String {
        if playbackService.duration > 0,
           playbackService.elapsed >= playbackService.duration - 0.25 {
            return "arrow.counterclockwise.circle.fill"
        }
        return playbackService.state == .playing ? "pause.circle.fill" : "play.circle.fill"
    }

    private func transportButton(
        _ image: String,
        size: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: size, weight: .medium))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? palette.ink : palette.ink.opacity(0.22))
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

    @Environment(\.playerPalette) private var palette
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
                    .fill(palette.ink.opacity(0.22))
                    .frame(height: 3)
                Capsule()
                    .fill(palette.ink)
                    .frame(width: width * progress, height: 3)
                Circle()
                    .fill(palette.ink)
                    .frame(width: 10, height: 10)
                    .overlay {
                        if isDragging {
                            Circle().fill(palette.ink.opacity(0.1)).frame(width: 28, height: 28)
                        }
                    }
                    .offset(x: width * progress - 5)
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
