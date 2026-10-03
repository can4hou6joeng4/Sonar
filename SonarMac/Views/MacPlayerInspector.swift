import SwiftUI

struct MacPlayerInspector: View {
    let model: MacAppModel
    @SceneStorage("macInspectorTab") private var tab = "queue"

    var body: some View {
        VStack(spacing: 0) {
            Picker("正在播放", selection: $tab) {
                Text("待播清单").tag("queue")
                Text("歌词").tag("lyrics")
            }.pickerStyle(.segmented).padding(16)
            if tab == "queue" { queue } else { lyrics }
        }
    }

    private var queue: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.playback.queue.tracks.count) 首歌曲").foregroundStyle(.secondary)
                Spacer()
                Button("清除待播") { model.playback.clearUpcoming() }
                    .disabled(model.playback.queue.tracks.count < 2)
            }.font(.caption).padding(.horizontal, 16).padding(.bottom, 8)
            List {
                ForEach(Array(model.playback.queue.tracks.enumerated()), id: \.offset) { index, track in
                    HStack(spacing: 10) {
                        MacArtworkView(track: track, service: model.artworkService, size: 36, radius: 6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title).lineLimit(1).fontWeight(index == model.playback.queue.currentIndex ? .semibold : .regular)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if index == model.playback.queue.currentIndex { Image(systemName: "waveform").foregroundStyle(.tint) }
                    }.padding(.vertical, 4).contentShape(Rectangle())
                    .onTapGesture(count: 2) { Task { await model.playback.selectQueueItem(at: index) } }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction { Task { await model.playback.selectQueueItem(at: index) } }
                    .contextMenu {
                        Button("播放") { Task { await model.playback.selectQueueItem(at: index) } }
                        Button("收藏") { model.collect(track) }
                        Button("移除", role: .destructive) { Task { await model.playback.removeQueueItem(at: index) } }
                    }
                }
                .onMove { model.playback.moveQueueItems(fromOffsets: $0, toOffset: $1) }
            }.listStyle(.inset)
            .overlay {
                if model.playback.queue.tracks.isEmpty {
                    MacEmptyState(title: "待播清单为空", description: "播放一首歌曲，音乐会从这里继续。", symbol: "text.line.first.and.arrowtriangle.forward")
                }
            }
        }
    }

    @ViewBuilder private var lyrics: some View {
        if let lyrics = model.lyrics, !lyrics.lines.isEmpty {
            MacSynchronizedLyrics(document: lyrics, playback: model.playback)
        } else {
            MacEmptyState(title: model.playback.queue.current == nil ? "尚未播放" : "暂无歌词", description: "可用的歌词会随音乐同步显示。", symbol: "quote.bubble")
        }
    }
}

private struct MacSynchronizedLyrics: View {
    let document: LyricsDocument
    let playback: PlaybackService
    @State private var followsPlayback = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var currentIndex: Int? { document.currentIndex(at: playback.elapsed) }

    var body: some View {
        VStack(spacing: 0) {
            Toggle("跟随播放", isOn: $followsPlayback).toggleStyle(.switch).controlSize(.small)
                .padding(.horizontal, 20).padding(.bottom, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(Array(document.lines.enumerated()), id: \.element.id) { index, line in
                            Button { Task { await playback.seek(to: line.time) } } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(line.text).font(.system(size: 23, weight: index == currentIndex ? .bold : .medium))
                                    if let translated = document.translation(for: line) { Text(translated).font(.callout) }
                                }
                                .foregroundStyle(index == currentIndex ? Color.primary : Color.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).id(index).help("跳转到 \(macTime(line.time))")
                        }
                    }.padding(24)
                }
                .onChange(of: currentIndex) { _, index in
                    guard followsPlayback, let index else { return }
                    scroll(to: index, proxy: proxy)
                }
                .onChange(of: followsPlayback) { _, follows in
                    if follows, let index = currentIndex { scroll(to: index, proxy: proxy) }
                }
                .task(id: document.lines.first?.id) {
                    await Task.yield()
                    if followsPlayback, let index = currentIndex { proxy.scrollTo(index, anchor: .center) }
                }
            }
        }
    }

    private func scroll(to index: Int, proxy: ScrollViewProxy) {
        if reduceMotion { proxy.scrollTo(index, anchor: .center) }
        else { withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(index, anchor: .center) } }
    }
}
