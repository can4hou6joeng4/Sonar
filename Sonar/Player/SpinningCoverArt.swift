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
            vinylDisc
                .rotationEffect(.degrees(rotation(at: timeline.date) * 360))
        }
        .frame(width: size, height: size)
        .id(track?.musicID ?? "empty-artwork")
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
        .accessibilityHidden(true)
    }

    private var vinylDisc: some View {
        let labelSize = size * NCMDesignTokens.Player.artworkRatio
        return ZStack {
            Circle().fill(Color(hex: "#0D0D0F") ?? .black)
            VinylGrooves()
                .padding(size * 0.018)
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.13), location: 0),
                    .init(color: .clear, location: 0.34),
                    .init(color: .clear, location: 0.62),
                    .init(color: .white.opacity(0.07), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(Circle())
            .rotationEffect(.degrees(38))

            PlayerArtwork(track: track, size: labelSize, circular: true)
                .overlay(Circle().stroke(.black.opacity(0.42), lineWidth: 1))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.42), radius: 20, y: 16)
    }

    private func rotation(at date: Date) -> Double {
        guard isPlaying, !reduceMotion else { return accumulatedTurns }
        return accumulatedTurns + date.timeIntervalSince(startedAt) / AppMotion.discRotation
    }
}

private struct VinylGrooves: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maximumRadius = min(size.width, size.height) / 2
            var radius: CGFloat = 5
            var index = 0
            while radius < maximumRadius {
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(index.isMultiple(of: 2) ? .white.opacity(0.055) : .black.opacity(0.35)),
                    lineWidth: index.isMultiple(of: 2) ? 0.72 : 0.9
                )
                radius += 2.2
                index += 1
            }
        }
        .clipShape(Circle())
    }
}
