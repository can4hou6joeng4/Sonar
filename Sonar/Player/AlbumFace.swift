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
                    RotatingAlbumArtwork(
                        track: playbackService.queue.current,
                        size: artworkSize,
                        isPlaying: playbackService.state == .playing,
                        reduceMotion: reduceMotion
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

private struct RotatingAlbumArtwork: View {
    let track: Track?
    let size: CGFloat
    let isPlaying: Bool
    let reduceMotion: Bool

    @State private var accumulatedTurns = 0.0
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying || reduceMotion)) { timeline in
            PlayerArtwork(track: track, size: size, circular: true)
                .rotationEffect(.degrees(rotation(at: timeline.date) * 360))
        }
        .frame(width: size, height: size)
        .id(track?.musicID ?? "empty-artwork")
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.88)),
                removal: .opacity.combined(with: .scale(scale: 0.88))
            )
        )
        .animation(AppMotion.emphasized(duration: AppMotion.long, reduceMotion: reduceMotion), value: track?.musicID)
        .onChange(of: isPlaying) { wasPlaying, nowPlaying in
            if wasPlaying {
                accumulatedTurns = rotation(at: Date()).truncatingRemainder(dividingBy: 1)
            }
            if nowPlaying { startedAt = Date() }
        }
        .onChange(of: track?.musicID) { _, _ in
            accumulatedTurns = 0
            startedAt = Date()
        }
    }

    private func rotation(at date: Date) -> Double {
        guard isPlaying, !reduceMotion else { return accumulatedTurns }
        return accumulatedTurns + date.timeIntervalSince(startedAt) / 24
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
