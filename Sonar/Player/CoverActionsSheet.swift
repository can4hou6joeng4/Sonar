import SwiftUI

struct PersonalPlaylistActionPresentation: Equatable {
    let isCollected: Bool
    let playlistName: String

    var icon: String { isCollected ? "heart.slash" : "heart" }
    var title: String { isCollected ? "移出 \(playlistName)" : "收藏到 \(playlistName)" }
    var subtitle: String {
        isCollected ? "从个人歌单移除，当前播放不会中断" : "将当前歌曲保存到个人歌单"
    }
    var identifier: String {
        isCollected ? "player-cover-remove-from-playlist" : "player-cover-collect-to-playlist"
    }
}

struct CoverActionsSheet: View {
    let track: Track
    let playlistAction: PersonalPlaylistActionPresentation
    let onAddToQueue: () -> Void
    let onToggleCollection: () -> Void
    let onSelectQuality: () -> Void

    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: track.title,
                subtitle: "\(playbackService.preferredQuality.title) · \(track.artist)"
            )
            .accessibilityIdentifier("player-cover-actions-sheet")
            ScrollView {
                LazyVStack(spacing: 4) {
                    actionRow(
                        icon: "text.badge.plus",
                        title: "加入待播放",
                        subtitle: "将当前歌曲添加到待播放末尾",
                        identifier: "player-cover-add-to-queue"
                    ) {
                        onAddToQueue()
                    }
                    actionRow(
                        icon: playlistAction.icon,
                        title: playlistAction.title,
                        subtitle: playlistAction.subtitle,
                        identifier: playlistAction.identifier
                    ) {
                        onToggleCollection()
                    }
                    actionRow(
                        icon: "waveform.badge.magnifyingglass",
                        title: "切换播放音质",
                        subtitle: "选择当前歌曲的其他可用音质",
                        identifier: "player-cover-quality"
                    ) {
                        onSelectQuality()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(scheme.surfaceContainerLow.ignoresSafeArea())
    }

    private func actionRow(
        icon: String,
        title: String,
        subtitle: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                bubble(systemImage: icon)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(scheme.onSurface)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(scheme.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .background(scheme.surfaceContainer, in: RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func bubble(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(scheme.onSecondaryContainer)
            .frame(width: 36, height: 36)
            .background(scheme.secondaryContainer, in: Circle())
    }
}
