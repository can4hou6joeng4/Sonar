import SwiftUI

struct SongRow: View {
    enum Leading: Equatable {
        case cover
        case index(Int)
    }

    enum Trailing: Equatable {
        case play
        case more
    }

    let track: Track
    var leading: Leading = .cover
    var trailing: Trailing = .more
    var showAlbum = true
    var showDivider = true
    var isCurrent = false
    var isSelected = false
    var isPlaying = false
    var onPlay: () -> Void
    var onAction: (() -> Void)?

    @Environment(\.m3Scheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                HStack(spacing: 10) {
                    leadingView
                    labels
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("song-row-play-\(track.musicID)")

            trailingButton
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .frame(height: NCMDesignTokens.Layout.songRowHeight)
        .background(rowBackground)
        .overlay(alignment: .bottomTrailing) {
            if showDivider {
                Rectangle()
                    .fill(scheme.outlineVariant)
                    .frame(height: 0.5)
                    .padding(.leading, dividerInset)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leadingView: some View {
        switch leading {
        case .cover:
            PlayerArtwork(track: track, size: 44, cornerRadius: 6)
        case let .index(index):
            Group {
                if isCurrent {
                    PlayingEqualizer(isAnimating: isPlaying, color: scheme.primary)
                } else {
                    Text("\(index)")
                        .font(.system(size: 14))
                        .foregroundStyle(scheme.outline)
                }
            }
            .frame(width: 26, height: 44)
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if isCurrent, leading == .cover {
                    PlayingEqualizer(isAnimating: isPlaying, color: primaryForeground)
                }
                Text(track.title)
                    .font(.system(size: NCMDesignTokens.Typography.songTitle))
                    .foregroundStyle(primaryForeground)
                    .lineLimit(1)
            }
            HStack(spacing: 5) {
                QualityBadge(quality: track.highestKnownQuality)
                Text(subtitle)
                    .font(.system(size: NCMDesignTokens.Typography.songSubtitle))
                    .foregroundStyle(secondaryForeground)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var trailingButton: some View {
        switch trailing {
        case .play:
            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(scheme.onSurface)
                    .frame(width: 34, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放 \(track.title)")
        case .more:
            if let onAction {
                Button(action: onAction) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(scheme.onSurfaceVariant)
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("更多")
                .accessibilityIdentifier("song-row-more-\(track.musicID)")
            } else {
                Color.clear.frame(width: 32, height: 44)
            }
        }
    }

    private var subtitle: String {
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = showAlbum && !album.isEmpty && album != track.title
            ? [track.artist, album]
            : [track.artist]
        return values.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var dividerInset: CGFloat {
        switch leading {
        case .cover: 70
        case .index: 52
        }
    }

    private var rowBackground: Color {
        if isSelected { return scheme.primaryContainer.opacity(0.56) }
        if isCurrent { return scheme.primaryContainer.opacity(0.12) }
        return .clear
    }

    private var primaryForeground: Color {
        if isSelected { return scheme.onPrimaryContainer }
        if isCurrent { return scheme.primary }
        return scheme.onSurface
    }

    private var secondaryForeground: Color {
        if isSelected { return scheme.onPrimaryContainer.opacity(0.86) }
        if isCurrent { return scheme.primary.opacity(0.86) }
        return scheme.onSurfaceVariant
    }
}
