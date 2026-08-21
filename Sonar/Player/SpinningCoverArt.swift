import SwiftUI

struct SpinningCoverArt: View {
    let track: Track?
    let size: CGFloat
    let isPlaying: Bool

    @Environment(\.sonarReduceMotion) private var reduceMotion
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
