import SwiftUI

/// A compact control group sharing the app's root playback service.
struct MacPlaybackControls: View {
    let playback: PlaybackService

    private var playLabel: String {
        if case .failed = playback.state { return "重试播放" }
        if playback.state == .loading, playback.playbackRequested { return "取消加载" }
        return playback.playbackRequested ? "暂停" : "播放"
    }

    private var modeTitle: String {
        switch playback.playbackMode {
        case .shuffle: "随机播放"
        case .repeatOne: "单曲循环"
        case .playInOrder: "顺序播放"
        case .sequence: "歌单循环"
        }
    }

    private var modeSymbol: String {
        switch playback.playbackMode {
        case .shuffle: "shuffle"
        case .repeatOne: "repeat.1"
        case .playInOrder: "arrow.right"
        case .sequence: "repeat"
        }
    }

    private var modeDescription: String {
        switch playback.playbackMode {
        case .shuffle: "随机播放歌单中的歌曲"
        case .repeatOne: "当前歌曲结束后重新播放"
        case .playInOrder: "按顺序播放，到歌单末尾停止"
        case .sequence: "按顺序播放，歌单结束后从头开始"
        }
    }

    private var volumeSymbol: String {
        if playback.volume == 0 { return "speaker.slash" }
        return playback.volume < 0.5 ? "speaker.wave.1" : "speaker.wave.2"
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                Button(action: cyclePlaybackMode) {
                    controlIcon(modeSymbol)
                }
                .help("\(modeTitle) · \(modeDescription) · 点击切换播放模式")
                .accessibilityLabel("切换播放模式")
                .accessibilityValue(modeTitle)

                HStack(spacing: 2) {
                    Button { Task { await playback.previous() } } label: {
                        controlIcon("backward.end.fill")
                    }
                    .help("上一首").accessibilityLabel("上一首")

                    Button { Task { await playback.togglePlayback() } } label: {
                        controlIcon(playback.playbackRequested ? "pause.fill" : "play.fill")
                    }
                    .help(playLabel).accessibilityLabel(playLabel)

                    Button { Task { await playback.next() } } label: {
                        controlIcon("forward.end.fill")
                    }
                    .help("下一首").accessibilityLabel("下一首")
                }
                .disabled(playback.queue.current == nil)
            }

            Divider().frame(height: 12).accessibilityHidden(true)

            HStack(spacing: 4) {
                Image(systemName: volumeSymbol)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { playback.volume }, set: { playback.setVolume($0) }), in: 0...1)
                    .controlSize(.mini)
                    .frame(width: 48)
                    .accessibilityLabel("音量")
                    .help("音量：\(Int((playback.volume * 100).rounded()))%")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("播放控制")
    }

    private func controlIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .frame(width: 20, height: 24)
            .contentShape(Rectangle())
    }

    private func cyclePlaybackMode() {
        let next: PlaybackService.PlaybackMode
        switch playback.playbackMode {
        case .shuffle: next = .repeatOne
        case .repeatOne: next = .playInOrder
        case .playInOrder: next = .sequence
        case .sequence: next = .shuffle
        }
        playback.setPlaybackMode(next)
    }
}
