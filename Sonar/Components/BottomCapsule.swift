import SwiftUI

struct NCMTextTabBar: View {
    @Environment(\.m3Scheme) private var scheme

    let selectedTab: ShellTab
    let safeBottom: CGFloat
    let onSelect: (ShellTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ShellTab.allCases) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    Text(tab.title)
                        .font(.system(
                            size: tab == selectedTab
                                ? NCMDesignTokens.Typography.selectedTab
                                : NCMDesignTokens.Typography.tab,
                            weight: tab == selectedTab ? .bold : .regular
                        ))
                        .foregroundStyle(tab == selectedTab ? scheme.onSurface : scheme.onSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: NCMDesignTokens.Layout.tabBarHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == selectedTab ? .isSelected : [])
                .accessibilityIdentifier(tab.accessibilityIdentifier)
            }
        }
        .padding(.bottom, safeBottom)
        .frame(height: NCMDesignTokens.Layout.tabBarHeight + safeBottom, alignment: .top)
        .background(.ultraThinMaterial)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 14,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 14,
            style: .continuous
        ))
    }
}

struct NCMMiniPlayer: View {
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme

    let onOpenPlayer: () -> Void
    let onOpenQueue: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenPlayer) {
                HStack(spacing: 10) {
                    SpinningCoverArt(
                        track: playbackService.queue.current,
                        size: NCMDesignTokens.Layout.miniArtworkSize,
                        isPlaying: playbackService.state == .playing
                    )
                    .accessibilityIdentifier("mini-player-cover")

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(playbackService.queue.current?.title ?? "暂无播放")
                            .font(.system(size: NCMDesignTokens.Typography.miniPlayer, weight: .medium))
                            .foregroundStyle(scheme.onSurface)
                            .lineLimit(1)
                        Text(playbackService.queue.current.map { "- \($0.artist)" } ?? "- 选择歌曲开始播放")
                            .font(.system(size: NCMDesignTokens.Typography.miniPlayer, weight: .regular))
                            .foregroundStyle(scheme.onSurfaceVariant)
                            .lineLimit(1)
                            .frame(maxWidth: 150, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("打开播放页")
            .accessibilityIdentifier("mini-player-title")

            Button {
                Task { await playbackService.togglePlayback() }
            } label: {
                Image(systemName: playbackService.state == .playing ? "pause.circle" : "play.circle")
                    .font(.system(size: 30, weight: .regular))
                    .frame(width: NCMDesignTokens.Layout.miniControlSize, height: NCMDesignTokens.Layout.miniControlSize)
            }
            .buttonStyle(.plain)
            .foregroundStyle(scheme.onSurface)
            .disabled(playbackService.queue.current == nil || playbackService.state == .loading)
            .accessibilityLabel(playbackService.state == .playing ? "暂停" : "播放")
            .accessibilityIdentifier("mini-player-play-pause")

            Button(action: onOpenQueue) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 26, weight: .regular))
                    .frame(width: NCMDesignTokens.Layout.miniControlSize, height: NCMDesignTokens.Layout.miniControlSize)
            }
            .buttonStyle(.plain)
            .foregroundStyle(scheme.onSurface)
            .disabled(playbackService.queue.current == nil)
            .accessibilityLabel("播放队列")
            .accessibilityIdentifier("mini-player-queue")
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: NCMDesignTokens.Layout.miniPlayerHeight)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.07), radius: 6, y: 2)
        .contentShape(Capsule())
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
}
