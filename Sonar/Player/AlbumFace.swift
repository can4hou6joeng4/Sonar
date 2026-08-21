import QuartzCore
import SwiftUI

struct AlbumFace: View {
    let lyrics: LyricsDocument
    let onCoverAction: () -> Void

    @Environment(PlaybackService.self) private var playbackService
    @Environment(UIPlaybackPreferences.self) private var preferences
    @Environment(\.playerPalette) private var palette
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.sonarReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let artworkSize = min(max(min(proxy.size.width * 0.86, proxy.size.height * 0.62), 160), 360)
            let showMiniLyrics = preferences.miniLyricsEnabled && !lyrics.lines.isEmpty

            ZStack(alignment: .bottomLeading) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    SpinningCoverArt(
                        track: playbackService.queue.current,
                        size: artworkSize,
                        isPlaying: playbackService.state == .playing
                    )
                    .shadow(color: .black.opacity(0.16), radius: 28, y: 18)
                    .contentShape(Circle())
                    .onTapGesture(perform: onCoverAction)
                    .accessibilityLabel("封面操作")
                    .accessibilityIdentifier("player-album-cover")

                    Text(playbackService.queue.current?.album.nonEmpty ?? "未知专辑")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.muted.opacity(0.78))
                        .lineLimit(1)
                        .padding(.top, 22)
                        .frame(maxWidth: proxy.size.width * 0.86)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: showMiniLyrics ? -36 : 0)
                .animation(
                    AppMotion.emphasized(duration: AppMotion.medium, reduceMotion: reduceMotion),
                    value: showMiniLyrics
                )

                if showMiniLyrics {
                    MiniLyricsPanel(document: lyrics)
                        .frame(width: min(320, proxy.size.width * 0.78), height: 84)
                        .padding(.bottom, 20)
                }
            }
        }
    }
}

private struct MiniLyricsPanel: View {
    let document: LyricsDocument

    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.sonarReduceMotion) private var reduceMotion

    private var currentIndex: Int {
        document.currentIndex(at: playbackService.elapsed) ?? 0
    }

    private var visibleIndices: Range<Int> {
        let maxStart = max(0, document.lines.count - 3)
        let start = min(max(currentIndex - 1, 0), maxStart)
        return start..<min(start + 3, document.lines.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleIndices), id: \.self) { index in
                Text(document.lines[index].text)
                    .font(.system(size: index == currentIndex ? 14 : 12.5, weight: .regular))
                    .foregroundStyle(
                        index == currentIndex
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant.opacity(0.72)
                    )
                    .blur(radius: index == currentIndex || reduceMotion ? 0 : 0.7)
                    .lineLimit(1)
                    .frame(height: 22, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(
            AppMotion.emphasized(duration: 0.38, reduceMotion: reduceMotion),
            value: currentIndex
        )
        .accessibilityIdentifier("mini-lyrics-panel")
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
