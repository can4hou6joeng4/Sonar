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
    var onShareLyricsCard: (() -> Void)? = nil

    @Environment(PlaybackService.self) private var playbackService
    @Environment(SleepTimer.self) private var sleepTimer
    @Environment(\.m3Scheme) private var scheme
    @State private var showsSleepOptions = false
    @State private var showsRateOptions = false

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
                    .disabled(!track.source.isEnabled)
                    actionRow(
                        icon: playlistAction.icon,
                        title: playlistAction.title,
                        subtitle: playlistAction.subtitle,
                        identifier: playlistAction.identifier
                    ) {
                        onToggleCollection()
                    }
                    actionRow(
                        icon: "moon.zzz",
                        title: "定时关闭",
                        subtitle: sleepTimer.remainingText ?? "播放到设定时间后自动暂停",
                        identifier: "player-cover-sleep-timer"
                    ) {
                        showsSleepOptions = true
                    }
                    actionRow(
                        icon: "speedometer",
                        title: "播放速度",
                        subtitle: rateLabel(playbackService.playbackRate),
                        identifier: "player-cover-playback-rate"
                    ) {
                        showsRateOptions = true
                    }
                    if let onShareLyricsCard {
                        actionRow(
                            icon: "text.quote",
                            title: "分享歌词卡片",
                            subtitle: "生成一张带歌词的图片分享出去",
                            identifier: "player-cover-share-lyrics"
                        ) {
                            onShareLyricsCard()
                        }
                    }
                    actionRow(
                        icon: "waveform.badge.magnifyingglass",
                        title: "切换播放音质",
                        subtitle: "选择当前歌曲的其他可用音质",
                        identifier: "player-cover-quality"
                    ) {
                        onSelectQuality()
                    }
                    .disabled(!track.source.isEnabled)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(scheme.surfaceContainerLow.ignoresSafeArea())
        .confirmationDialog("定时关闭", isPresented: $showsSleepOptions, titleVisibility: .visible) {
            ForEach([15, 30, 60, 90], id: \.self) { minutes in
                Button("\(minutes) 分钟") {
                    sleepTimer.start(minutes: minutes) {
                        Task { await playbackService.pause() }
                    }
                }
            }
            if sleepTimer.isActive {
                Button("关闭定时", role: .destructive) { sleepTimer.cancel() }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("播放速度", isPresented: $showsRateOptions, titleVisibility: .visible) {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                Button(rateLabel(Float(rate))) {
                    playbackService.setPlaybackRate(Float(rate))
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func rateLabel(_ rate: Float) -> String {
        let value = Double(rate)
        if value == value.rounded() { return String(format: "%.0fx", value) }
        return String(format: "%gx", value)
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
