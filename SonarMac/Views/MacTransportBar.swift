import SwiftUI

struct MacTransportBar: View {
    let model: MacAppModel
    private var playback: PlaybackService { model.playback }
    private var track: Track? { playback.queue.current }
    private var togglePlaybackLabel: String {
        if case .failed = playback.state { return "重试播放" }
        if playback.state == .loading, playback.playbackRequested { return "取消加载" }
        return playback.playbackRequested ? "暂停" : "播放"
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 24) {
                HStack(spacing: 12) {
                    MacArtworkView(track: track, service: model.artworkService, size: 50)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track?.title ?? "让音乐开始吧").fontWeight(.medium).lineLimit(1)
                        Text(track?.artist ?? "搜索并播放你喜欢的歌曲").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let track {
                        Button { model.collect(track) } label: {
                            Image(systemName: model.libraryTracks.contains(where: { $0.musicID == track.musicID }) ? "heart.fill" : "heart")
                        }.buttonStyle(.plain).help("收藏到个人歌单")
                    }
                }.frame(minWidth: 180, maxWidth: 310)
                VStack(spacing: 5) {
                    HStack(spacing: 22) {
                        Button { playback.setPlaybackMode(playback.playbackMode == .shuffle ? .sequence : .shuffle) } label: {
                            Image(systemName: "shuffle").foregroundStyle(playback.playbackMode == .shuffle ? Color.accentColor : Color.secondary)
                        }.help("随机播放").accessibilityValue(playback.playbackMode == .shuffle ? "开启" : "关闭")
                        Button { Task { await playback.previous() } } label: { Image(systemName: "backward.end.fill") }
                            .help("上一首")
                        Button { Task { await playback.togglePlayback() } } label: {
                            Group {
                                if playback.state == .loading { ProgressView().controlSize(.small) }
                                else { Image(systemName: playback.state == .playing ? "pause.fill" : "play.fill") }
                            }.font(.title2).frame(width: 28, height: 25)
                        }.help(togglePlaybackLabel).accessibilityLabel(togglePlaybackLabel)
                        Button { Task { await playback.next() } } label: { Image(systemName: "forward.end.fill") }
                            .help("下一首")
                        Button { playback.setPlaybackMode(playback.playbackMode == .repeatOne ? .sequence : .repeatOne) } label: {
                            Image(systemName: playback.playbackMode == .repeatOne ? "repeat.1" : "repeat")
                                .foregroundStyle(playback.playbackMode == .repeatOne ? Color.accentColor : Color.secondary)
                        }.help("单曲循环").accessibilityValue(playback.playbackMode == .repeatOne ? "开启" : "关闭")
                    }.buttonStyle(.plain).disabled(track == nil)
                    HStack(spacing: 8) {
                        Text(macTime(playback.elapsed)).frame(width: 35, alignment: .trailing)
                        MacSeekSlider(playback: playback)
                        Text(macTime(playback.duration)).frame(width: 35, alignment: .leading)
                    }.font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }.frame(minWidth: 220, maxWidth: 500)
                HStack(spacing: 8) {
                    Image(systemName: playback.volume == 0 ? "speaker.slash" : "speaker.wave.2").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { playback.volume }, set: { playback.setVolume($0) }), in: 0...1)
                        .controlSize(.small).frame(width: 95).accessibilityLabel("音量")
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(.horizontal, 22).padding(.vertical, 14)
        }.background(.bar)
    }
}
