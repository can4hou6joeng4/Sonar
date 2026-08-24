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

struct AlbumFace: View {
    let lyrics: LyricsDocument
    let onCoverAction: () -> Void

    @Environment(PlaybackService.self) private var playbackService

    var body: some View {
        GeometryReader { proxy in
            let disc = VinylGeometry.discDiameter(
                width: proxy.size.width,
                height: proxy.size.height
            )
            let clearance = disc * NCMDesignTokens.Player.discTopClearanceRatio
            let tonearm = VinylGeometry.tonearmFrame(disc: disc)

            ZStack(alignment: .topLeading) {
                SpinningCoverArt(
                    track: playbackService.queue.current,
                    size: disc,
                    isPlaying: playbackService.state == .playing
                )
                .offset(y: clearance)

                NCMTonearm(isPlaying: playbackService.state == .playing)
                    .frame(width: tonearm.width, height: tonearm.height)
                    .offset(x: tonearm.minX, y: clearance + tonearm.minY)
            }
            .frame(width: disc, height: disc + clearance)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture(perform: onCoverAction)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("显示歌词")
            .accessibilityIdentifier("player-album-cover")
        }
    }
}

private struct NCMTonearm: View {
    let isPlaying: Bool

    @Environment(\.sonarReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / 100
            let scaleY = size.height / 100
            let pivot = CGPoint(x: 14 * scaleX, y: 14 * scaleY)
            let elbow = CGPoint(x: 58 * scaleX, y: 62 * scaleY)
            let head = CGPoint(x: 86 * scaleX, y: 88 * scaleY)

            var arm = Path()
            arm.move(to: pivot)
            arm.addLine(to: elbow)
            arm.addLine(to: head)
            context.stroke(arm, with: .color(.black.opacity(0.62)), style: StrokeStyle(lineWidth: 7 * scaleX, lineCap: .round, lineJoin: .round))
            context.stroke(arm, with: .linearGradient(
                Gradient(colors: [Color(hex: "#DDDCD8") ?? .white, Color(hex: "#8D8B87") ?? .gray]),
                startPoint: pivot,
                endPoint: head
            ), style: StrokeStyle(lineWidth: 4.5 * scaleX, lineCap: .round, lineJoin: .round))

            context.fill(
                Path(ellipseIn: CGRect(x: 3 * scaleX, y: 3 * scaleY, width: 22 * scaleX, height: 22 * scaleY)),
                with: .color(.black.opacity(0.68))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: 5 * scaleX, y: 5 * scaleY, width: 18 * scaleX, height: 18 * scaleY)),
                with: .radialGradient(
                    Gradient(colors: [Color(hex: "#ECEBE7") ?? .white, Color(hex: "#8B8984") ?? .gray]),
                    center: pivot,
                    startRadius: 0,
                    endRadius: 11 * scaleX
                )
            )
            context.fill(
                Path(roundedRect: CGRect(x: 80 * scaleX, y: 83 * scaleY, width: 17 * scaleX, height: 10 * scaleY), cornerRadius: 2 * scaleX),
                with: .color(Color(hex: "#232326") ?? .black)
            )
        }
        .rotationEffect(
            .degrees(isPlaying ? 0 : -16),
            anchor: UnitPoint(
                x: NCMDesignTokens.Player.tonearmPivotRatio,
                y: NCMDesignTokens.Player.tonearmPivotRatio
            )
        )
        .animation(
            reduceMotion ? nil : .timingCurve(0.32, 0.72, 0, 1, duration: AppMotion.tonearm),
            value: isPlaying
        )
        .shadow(color: .black.opacity(0.45), radius: 5, y: 3)
        .accessibilityHidden(true)
    }
}
