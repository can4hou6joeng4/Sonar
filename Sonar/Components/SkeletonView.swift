import SwiftUI

/// 加载占位块。用轻微呼吸动画代替转圈，首屏观感更接近正式内容。
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var cornerRadius: CGFloat = 6

    @Environment(\.m3Scheme) private var scheme
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(scheme.surfaceContainerHighest)
            .frame(width: width, height: height)
            .opacity(dimmed ? 0.55 : 1)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: dimmed
            )
            .onAppear { dimmed = true }
            .accessibilityHidden(true)
    }
}

/// 歌曲行骨架：封面 44 + 两行文字。
struct SkeletonSongRow: View {
    var showsCover = true

    var body: some View {
        HStack(spacing: 12) {
            if showsCover {
                SkeletonBlock(width: 44, height: 44, cornerRadius: 6)
            } else {
                SkeletonBlock(width: 26, height: 14, cornerRadius: 4)
            }
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(width: 150, height: 13)
                SkeletonBlock(width: 210, height: 11)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .frame(height: 60)
    }
}

struct SkeletonSongList: View {
    var rows = 6
    var showsCover = true

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< rows, id: \.self) { _ in
                SkeletonSongRow(showsCover: showsCover)
            }
        }
        .accessibilityIdentifier("skeleton-song-list")
    }
}

/// 卡片网格骨架（专辑/歌单用）。
struct SkeletonCardRow: View {
    var cards = 3

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0 ..< cards, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBlock(width: 100, height: 100, cornerRadius: 8)
                    SkeletonBlock(width: 80, height: 10)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
