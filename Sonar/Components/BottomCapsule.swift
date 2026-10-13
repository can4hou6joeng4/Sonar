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
    @Environment(\.sonarReduceMotion) private var reduceMotion

    let safeAreaBottom: CGFloat
    let onOpenPlayer: () -> Void
    let onOpenQueue: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpenPlayer) {
                HStack(spacing: 10) {
                    PlayerArtwork(track: playbackService.queue.current, size: 44, cornerRadius: 8, animatesChanges: true)
                        .accessibilityIdentifier("mini-player-cover")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playbackService.queue.current?.title ?? "暂无播放")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(scheme.onSurface)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(scheme.onSurfaceVariant)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.cellHighlight)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("打开播放页")
            .accessibilityValue(MiniPlayerPresentation.accessibilityValue(
                state: playbackService.state,
                elapsed: playbackService.elapsed,
                duration: playbackService.duration
            ))
            .accessibilityIdentifier("mini-player-title")
            .accessibilityAction(named: Text("播放队列"), onOpenQueue)
            .contextMenu {
                Button("播放队列", systemImage: "list.bullet", action: onOpenQueue)
            }

            skipButton("backward.end.fill", label: "上一首", identifier: "mini-player-previous") {
                Task { await playbackService.previous() }
            }
            Button(action: togglePlayback) {
                Group {
                    switch playbackService.state {
                    case .loading:
                        ProgressView().tint(scheme.onSurface)
                    case .playing:
                        Image(systemName: "pause.circle")
                    case .failed:
                        Image(systemName: "arrow.clockwise.circle")
                    case .idle, .paused:
                        Image(systemName: "play.circle")
                    }
                }
                .font(.system(size: 28, weight: .regular))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.circleIcon(diameter: 38, haptic: false))
            .foregroundStyle(scheme.onSurface)
            .disabled(playbackService.queue.current == nil)
            .accessibilityLabel(playbackControlLabel)
            .accessibilityIdentifier("mini-player-play-pause")
            skipButton("forward.end.fill", label: "下一首", identifier: "mini-player-next") {
                Task { await playbackService.next() }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: SpotlightLayout.miniPlayerHeight)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(scheme.surfaceContainerHigh.opacity(0.70), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(scheme.onSurface.opacity(0.08), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                Capsule()
                    .fill(scheme.onSurface.opacity(0.50))
                    .frame(width: proxy.size.width * MiniPlayerPresentation.progress(
                        elapsed: playbackService.elapsed,
                        duration: playbackService.duration
                    ))
            }
            .frame(height: 2)
            .padding(.horizontal, 14)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    let horizontal = value.translation.width
                    guard abs(horizontal) > 36,
                          abs(horizontal) > abs(value.translation.height) else { return }
                    if horizontal < 0 {
                        Task { await playbackService.next() }
                    } else {
                        Task { await playbackService.previous() }
                    }
                }
        )
    }

    private var subtitle: String {
        let artist = playbackService.queue.current?.artist ?? "选择歌曲开始播放"
        switch playbackService.state {
        case .loading: return "正在加载 · \(artist)"
        case .failed: return "播放失败，点按重试"
        case .idle, .paused, .playing: return artist.isEmpty ? "未知歌手" : artist
        }
    }

    private func skipButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.light()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.circleIcon(diameter: 38, haptic: false))
        .foregroundStyle(scheme.onSurface)
        .disabled(playbackService.queue.current == nil)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
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
        guard playbackService.queue.current != nil else { return }
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
}
