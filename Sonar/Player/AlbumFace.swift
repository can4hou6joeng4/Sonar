import SwiftUI

enum VinylGeometry {
    static func discDiameter(width: CGFloat, height: CGFloat) -> CGFloat {
        max(0, min(
            width * NCMDesignTokens.Player.discWidthRatio,
            height / (1 + NCMDesignTokens.Player.discTopClearanceRatio)
        ))
    }

    static func tonearmFrame(disc: CGFloat) -> CGRect {
        let size = disc * NCMDesignTokens.Player.tonearmSizeRatio
        let pivot = size * NCMDesignTokens.Player.tonearmPivotRatio
        return CGRect(
            x: disc * 0.5 - pivot,
            y: disc * NCMDesignTokens.Player.tonearmTopRatio - pivot,
            width: size,
            height: size
        )
    }
}

enum PlayerArtworkTransitionMetrics {
    static func scale(progress: CGFloat, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 1 }
        return 0.90 + 0.10 * clamped(progress)
    }

    static func opacity(progress: CGFloat, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        return Double(0.25 + 0.75 * clamped(progress))
    }

    private static func clamped(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }
}

struct AlbumFace: View {
    let expansionProgress: CGFloat
    let onCoverAction: () -> Void

    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.sonarReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let artworkSize = max(180, min(proxy.size.width - 40, proxy.size.height - 20, 336))

            artwork(size: artworkSize)
            .frame(width: artworkSize, height: artworkSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture {
                AppHaptics.light()
                onCoverAction()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("显示歌词")
            .accessibilityIdentifier("player-album-cover")
        }
    }

    private func artwork(size: CGFloat) -> some View {
        let paused = playbackService.state == .paused && !reduceMotion
        let expansionScale = PlayerArtworkTransitionMetrics.scale(
            progress: expansionProgress,
            reduceMotion: reduceMotion
        )
        return PlayerArtwork(
            track: playbackService.queue.current,
            size: size,
            cornerRadius: 18
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.24), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
        .scaleEffect((paused ? 0.95 : 1) * expansionScale)
        .opacity(PlayerArtworkTransitionMetrics.opacity(
            progress: expansionProgress,
            reduceMotion: reduceMotion
        ))
        .shadow(
            color: .black.opacity(paused ? 0.28 : 0.44),
            radius: paused ? 20 : 34,
            y: paused ? 12 : 22
        )
        .animation(
            AppMotion.standardSpring(reduceMotion: reduceMotion),
            value: playbackService.state
        )
    }
}
