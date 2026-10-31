import SwiftUI

/// 面板里的歌词视图：与刘海共享同一份歌词文档和播放进度，保持紧凑排版。
struct MacPanelLyricsView: View {
    let document: LyricsDocument
    let playback: PlaybackService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var follows = true

    private var currentIndex: Int? { document.currentIndex(at: playback.elapsed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(document.lines.count) 行歌词")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Toggle("跟随播放", isOn: $follows)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help("跟随播放滚动歌词")
                    .accessibilityLabel("跟随播放滚动歌词")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(document.lines.enumerated()), id: \.element.id) { index, line in
                            Button { Task { await playback.seek(to: line.time) } } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(line.text)
                                        .font(.system(size: 14, weight: index == currentIndex ? .semibold : .regular))
                                    if let translated = document.translation(for: line) {
                                        Text(translated)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .foregroundStyle(index == currentIndex ? Color.primary : Color.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(index)
                            .help("跳转到 \(macTime(line.time))")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .onChange(of: currentIndex) { _, index in
                    guard follows, let index else { return }
                    scroll(to: index, proxy: proxy)
                }
                .onChange(of: follows) { _, follows in
                    if follows, let index = currentIndex { scroll(to: index, proxy: proxy) }
                }
                .task(id: document.lines.first?.id) {
                    await Task.yield()
                    if follows, let index = currentIndex { proxy.scrollTo(index, anchor: .center) }
                }
            }
        }
    }

    private func scroll(to index: Int, proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(index, anchor: .center)
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(index, anchor: .center) }
        }
    }
}
