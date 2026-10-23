import SwiftUI

/// 歌曲操作项。
struct SongAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    var role: ButtonRole?
    var isEnabled: Bool = true
    /// 执行后是否收起面板；需要二次确认的操作设为 false。
    var dismissesOnPerform: Bool = true
    let perform: () -> Void
}

/// 统一的歌曲操作面板（替代各处的 confirmationDialog）。
///
/// 结构照网易云：顶部歌曲信息（封面/歌名/歌手·专辑/音质或下架状态），
/// 中间是带图标的操作行，底部独立「取消」。行高 52，分割线从文字处内缩。
struct SongActionsSheet: View {
    let track: Track
    let actions: [SongAction]
    var onCollect: (() -> Void)? = nil
    let onCancel: () -> Void

    private var shareURL: URL? {
        guard track.source == .wy, !track.songmid.isEmpty else { return nil }
        return URL(string: "https://music.163.com/song?id=\(track.songmid)")
    }

    @Environment(\.m3Scheme) private var scheme

    private var sheetHeight: CGFloat {
        let header: CGFloat = 88
        let row: CGFloat = 52
        let cancel: CGFloat = 64
        let share: CGFloat = shareURL == nil ? 0 : row
        return min(700, header + row * CGFloat(actions.count) + share + cancel)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(scheme.outlineVariant)
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                row(action, isLast: index == actions.count - 1)
            }
            if let shareURL {
                shareRow(url: shareURL)
            }
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Text("取消")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(scheme.onSurface)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(scheme.surfaceContainer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(height: sheetHeight, alignment: .top)
        .background(scheme.appSurface.ignoresSafeArea())
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(scheme.appSurface)
    }

    private var header: some View {
        HStack(spacing: 12) {
            PlayerArtwork(track: track, size: 56, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(scheme.onSurface)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !track.source.isEnabled {
                        Text("不可用")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(scheme.onSurfaceVariant)
                            .padding(.horizontal, 5)
                            .frame(height: 15)
                            .background(scheme.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    } else if !track.isPlayable {
                        Text("已下架")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(scheme.onSurfaceVariant)
                            .padding(.horizontal, 5)
                            .frame(height: 15)
                            .background(scheme.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    } else {
                        QualityBadge(quality: track.highestKnownQuality)
                    }
                    Text(metadata)
                        .font(.system(size: 12.5))
                        .foregroundStyle(scheme.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let onCollect {
                Button {
                    AppHaptics.light()
                    onCollect()
                    onCancel()
                } label: {
                    Image(systemName: "heart")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(scheme.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收藏到歌单")
            }
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .frame(height: 88)
    }

    private var metadata: String {
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = [track.artist]
        if !album.isEmpty, album != track.title { parts.append(album) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func row(_ action: SongAction, isLast: Bool) -> some View {
        Button(role: action.role) {
            guard action.isEnabled else { return }
            AppHaptics.light()
            action.perform()
            if action.dismissesOnPerform { onCancel() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 19, weight: .regular))
                    .frame(width: 22)
                Text(action.title)
                    .font(.system(size: 15.5))
                Spacer(minLength: 0)
            }
            .foregroundStyle(foreground(for: action))
            .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
            .frame(height: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle()
                        .fill(scheme.outlineVariant)
                        .frame(height: 0.5)
                        .padding(.leading, NCMDesignTokens.Layout.horizontalPadding + 34)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .accessibilityLabel(action.title)
    }

    private func shareRow(url: URL) -> some View {
        ShareLink(item: url, subject: Text(track.title), message: Text("\(track.title) - \(track.artist)")) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 19, weight: .regular))
                    .frame(width: 22)
                Text("分享")
                    .font(.system(size: 15.5))
                Spacer(minLength: 0)
            }
            .foregroundStyle(scheme.onSurface)
            .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
            .frame(height: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(scheme.outlineVariant)
                    .frame(height: 0.5)
                    .padding(.leading, NCMDesignTokens.Layout.horizontalPadding + 34)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("分享")
    }

    private func foreground(for action: SongAction) -> Color {
        if action.role == .destructive { return scheme.primary }
        return action.isEnabled ? scheme.onSurface : scheme.onSurfaceVariant.opacity(0.6)
    }
}

@MainActor
enum SongActionBuilder {
    static func standard(
        track: Track,
        playback: PlaybackService,
        toast: ToastCenter,
        collect: @escaping () -> Void
    ) -> [SongAction] {
        let playable = track.source.isEnabled && track.isPlayable
        var actions: [SongAction] = [
            SongAction(title: "立即播放", systemImage: "play.fill", isEnabled: playable) {
                Task { await playback.replaceQueue([track]) }
            },
            SongAction(title: "下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward", isEnabled: playable) {
                Task {
                    await playback.playNext(track)
                    toast.show("已设为下一首播放")
                }
            },
            SongAction(title: "加入待播放", systemImage: "text.badge.plus", isEnabled: playable) {
                Task {
                    let added = await playback.enqueue(track)
                    toast.show(added ? "已加入待播放" : "歌曲已在待播放中")
                }
            },
            SongAction(title: "收藏到歌单", systemImage: "music.note.list") { collect() },
            SongAction(title: "复制歌曲信息", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = "\(track.title) - \(track.artist)"
                toast.show("已复制歌曲信息")
            },
        ]
        if track.source == .wy, !track.songmid.isEmpty {
            actions.append(SongAction(title: "复制歌曲链接", systemImage: "link") {
                UIPasteboard.general.string = "https://music.163.com/song?id=\(track.songmid)"
                toast.show("已复制歌曲链接")
            })
        }
        return actions
    }
}

extension View {
    /// 以底部面板形式展示歌曲操作。
    func songActionsSheet(
        track: Binding<Track?>,
        onCollect: ((Track) -> Void)? = nil,
        actions: @escaping (Track) -> [SongAction]
    ) -> some View {
        sheet(item: track) { value in
            SongActionsSheet(
                track: value,
                actions: actions(value),
                onCollect: onCollect.map { handler in { handler(value) } },
                onCancel: { track.wrappedValue = nil }
            )
        }
    }
}
