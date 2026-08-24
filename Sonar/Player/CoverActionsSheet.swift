import SwiftUI

struct CoverActionsSheet: View {
    let track: Track
    let onAddToPlaylist: () -> Void
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
                        title: "添加到歌单",
                        subtitle: "选择歌单并立即添加当前歌曲",
                        identifier: "player-cover-add-to-playlist"
                    ) {
                        onAddToPlaylist()
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
