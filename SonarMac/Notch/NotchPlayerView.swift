import SwiftUI

struct NotchPlayerView: View {
    let model: MacAppModel
    let controller: NotchWindowController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var playback: PlaybackService { model.playback }
    private var track: Track? { playback.queue.current }

    var body: some View {
        VStack(spacing: 0) {
            compactHeader
            if controller.expanded { expandedContent }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.black, in: UnevenRoundedRectangle(
            topLeadingRadius: controller.geometry.hasNotch ? 8 : 18,
            bottomLeadingRadius: controller.expanded ? 28 : 18,
            bottomTrailingRadius: controller.expanded ? 28 : 18,
            topTrailingRadius: controller.geometry.hasNotch ? 8 : 18))
        .foregroundStyle(.white)
        .tint(.white)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        .onHover(perform: controller.hover)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: controller.expanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sonar 刘海播放器")
    }

    private var compactHeader: some View {
        HStack(spacing: 0) {
            cover.frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 6))
            Spacer(minLength: 8)
            if !controller.geometry.hasNotch {
                Text(controller.expanded ? "SONAR" : (track?.title ?? "SONAR"))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(track == nil || controller.expanded ? 3 : 0)
                    .lineLimit(1).foregroundStyle(.white.opacity(0.65))
            } else {
                Color.clear.frame(width: controller.geometry.centerGap)
            }
            Spacer(minLength: 8)
            NotchEqualizer(playing: playback.state == .playing, reduceMotion: reduceMotion)
                .frame(width: 24, height: 20)
        }
        .padding(.horizontal, 12)
        .frame(height: controller.geometry.topHeight)
        .contentShape(Rectangle())
        .onTapGesture { controller.toggleExpanded() }
        .accessibilityAction(named: controller.expanded ? "收起播放器" : "展开播放器") { controller.toggleExpanded() }
    }

    private var expandedContent: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                cover.frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(track?.title ?? "让音乐浮在手边")
                        .font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(track?.artist ?? "点击状态栏 Sonar 搜索或选择歌曲")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { controller.togglePinned() } label: {
                    Image(systemName: controller.pinned ? "pin.fill" : "pin")
                }.help(controller.pinned ? "取消固定，移开指针后收起" : "固定展开")
                    .accessibilityLabel(controller.pinned ? "取消固定播放器" : "固定播放器")
            }
            VStack(spacing: 2) {
                MacSeekSlider(playback: playback, title: "刘海播放进度",
                              onEditingChanged: controller.interactionChanged)
                HStack {
                    Text(time(playback.elapsed))
                    Spacer()
                    Text(time(playback.duration))
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
            }
            HStack(spacing: 28) {
                Button { if let track { model.toggleFavorite(track) } } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                }.help(isFavorite ? "取消收藏当前歌曲" : "收藏到个人歌单")
                    .accessibilityLabel(isFavorite ? "取消收藏当前歌曲" : "收藏当前歌曲")
                    .disabled(track == nil || model.library == nil)
                Spacer(minLength: 0)
                Button { Task { await playback.previous() } } label: { Image(systemName: "backward.end.fill") }.disabled(track == nil)
                    .accessibilityLabel("上一首")
                Button { Task { await playback.togglePlayback() } } label: {
                    if playback.state == .loading { ProgressView().controlSize(.small).frame(width: 24, height: 24) }
                    else { Image(systemName: playback.playbackRequested ? "pause.fill" : "play.fill").font(.system(size: 24)) }
                }.accessibilityLabel(model.playbackActionTitle).disabled(track == nil)
                Button { Task { await playback.next() } } label: { Image(systemName: "forward.end.fill") }.disabled(track == nil)
                    .accessibilityLabel("下一首")
                Spacer(minLength: 0)
                Button { controller.collapse(); openStatusPanel() } label: { Image(systemName: "music.note.list") }
                    .help("打开选歌面板").accessibilityLabel("打开 Sonar 状态栏面板")
                    .disabled(false)
            }.font(.system(size: 15))
            footer
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 16)
        .frame(height: 226)
    }

    @ViewBuilder private var footer: some View {
        if case .failed = playback.state {
            Button("暂时无法播放 · 点此重试") { Task { await playback.retryCurrent() } }
                .font(.system(size: 11)).foregroundStyle(.orange)
        } else if let lyrics = model.lyrics, let index = lyrics.currentIndex(at: playback.elapsed), let line = lyrics.line(at: index) {
            Text(line.text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.1")
                Slider(value: Binding(get: { playback.volume }, set: { playback.setVolume($0) }), in: 0...1,
                       onEditingChanged: controller.interactionChanged)
                    .controlSize(.mini).accessibilityLabel("刘海音量")
                Image(systemName: "speaker.wave.3")
            }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
        }
    }

    private var isFavorite: Bool {
        guard let track else { return false }
        return model.isFavorite(track)
    }

    @ViewBuilder private var cover: some View {
        if let image = model.artwork {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [.cyan.opacity(0.6), .indigo.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "waveform").resizable().scaledToFit().padding(7)
            }
        }
    }

    private func time(_ value: Double) -> String {
        let seconds = value.isFinite ? max(0, Int(value)) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func openStatusPanel() {
        NotificationCenter.default.post(name: .sonarOpenStatusPanel, object: nil)
    }
}

private struct NotchEqualizer: View {
    let playing: Bool
    let reduceMotion: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.14, paused: !playing || reduceMotion)) { context in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { index in
                    let phase = context.date.timeIntervalSinceReferenceDate * 5 + Double(index) * 1.4
                    Capsule().fill(.cyan.opacity(playing ? 0.9 : 0.4))
                        .frame(width: 3, height: playing ? (reduceMotion ? 10 : 5 + 12 * abs(sin(phase))) : 4)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.accessibilityLabel(playing ? "正在播放" : "已暂停")
    }
}
