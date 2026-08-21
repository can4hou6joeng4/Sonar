import SwiftUI

struct CoverActionsSheet: View {
    let track: Track
    let onAddToPlaylist: () -> Void
    let onSelectQuality: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(UIPlaybackPreferences.self) private var preferences
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.m3Scheme) private var scheme

    var body: some View {
        @Bindable var preferences = preferences

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
                        icon: "arrow.down.circle",
                        title: "下载当前歌曲",
                        subtitle: "选择音质并下载当前在线歌曲",
                        identifier: "player-cover-download"
                    ) {
                        dismiss()
                        toastCenter.show("已加入下载队列")
                    }
                    actionRow(
                        icon: "waveform.badge.magnifyingglass",
                        title: "切换播放音质",
                        subtitle: "选择当前歌曲的其他可用音质",
                        identifier: "player-cover-quality"
                    ) {
                        onSelectQuality()
                    }

                    HStack(spacing: 16) {
                        bubble(systemImage: "captions.bubble")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("显示迷你歌词")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(scheme.onSurface)
                            Text("在封面页左下角显示三行歌词")
                                .font(.system(size: 12.5))
                                .foregroundStyle(scheme.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("显示迷你歌词", isOn: $preferences.miniLyricsEnabled)
                            .labelsHidden()
                            .accessibilityIdentifier("player-cover-mini-lyrics-toggle")
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 64)
                    .background(scheme.surfaceContainer, in: RoundedRectangle(cornerRadius: 20))
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
