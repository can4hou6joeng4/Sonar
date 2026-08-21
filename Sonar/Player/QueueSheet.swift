import SwiftUI

struct QueueSheet: View {
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.playerPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(palette.ink.opacity(0.18))
                .frame(width: 38, height: 4)
                .padding(.top, 10)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("播放列表")
                        .font(.system(size: 22, weight: .semibold))
                        .accessibilityIdentifier("playback-queue-list")
                    Text("\(playbackService.queue.tracks.count) 首 · 顺序播放")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
                .accessibilityIdentifier("playback-queue-close")
            }
            .padding(.leading, 22)
            .padding(.trailing, 14)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Rectangle()
                .fill(palette.ink.opacity(0.08))
                .frame(height: 1)

            if playbackService.queue.tracks.isEmpty {
                ContentUnavailableView("播放列表为空", systemImage: "music.note.list")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(playbackService.queue.tracks.enumerated()), id: \.offset) { index, track in
                                queueRow(track: track, index: index)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear {
                        guard let index = playbackService.queue.currentIndex else { return }
                        Task { @MainActor in
                            await Task.yield()
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            }
        }
        .foregroundStyle(palette.ink)
        .background(palette.queueBackground.ignoresSafeArea())
    }

    private func queueRow(track: Track, index: Int) -> some View {
        let isCurrent = playbackService.queue.currentIndex == index
        return Button {
            Task { await playbackService.selectQueueItem(at: index) }
        } label: {
            HStack(spacing: 12) {
                PlayerArtwork(track: track, size: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(track.title)
                        .font(.system(size: 14.5, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? palette.ink : palette.ink.opacity(0.86))
                        .lineLimit(1)
                    Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isCurrent {
                    QueuePlayingBars(isPlaying: playbackService.state == .playing)
                } else {
                    Text(track.highestKnownQuality.badgeTitle.uppercased())
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(palette.muted.opacity(0.78))
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .frame(height: 66)
            .background(
                isCurrent ? palette.ink.opacity(0.075) : .clear,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(track.title)，\(track.artist)")
        .accessibilityIdentifier("playback-queue-row-\(index)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

private struct QueuePlayingBars: View {
    let isPlaying: Bool

    @Environment(\.playerPalette) private var palette
    @Environment(\.sonarReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying || reduceMotion)) { timeline in
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<5, id: \.self) { index in
                    let base = [12.0, 19.0, 15.0, 20.0, 11.0][index]
                    Capsule()
                        .fill(palette.ink)
                        .frame(width: 2.6, height: base * scale(index: index, date: timeline.date))
                }
            }
        }
        .frame(width: 24, height: 24, alignment: .bottom)
    }

    private func scale(index: Int, date: Date) -> Double {
        guard isPlaying, !reduceMotion else { return 0.55 }
        let wave = (sin(date.timeIntervalSinceReferenceDate / 0.92 * 2 * .pi + Double(index) * 1.18) + 1) / 2
        return 0.32 + wave * 0.68
    }
}
